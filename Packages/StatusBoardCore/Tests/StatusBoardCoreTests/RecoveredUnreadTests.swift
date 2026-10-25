import Foundation
import Testing
import SQLite3
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private func principal(account: String = "A", user: String = "U", expiry: Double = 10_000) throws -> [String: Any] {
    let payload = try JSONSerialization.data(withJSONObject: ["exp": expiry,
        "https://api.openai.com/auth": ["chatgpt_account_id": account, "user_id": user]])
        .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return ["authMethod": "chatgpt", "authToken": "fixture.\(payload).fixture"]
}

@Test func recoveryScopeRequiresMatchingUnexpiredAuthenticatedPrincipal() throws {
    let now = Date(timeIntervalSince1970: 100)
    let scope = try DesktopReadScope.authenticated(principal(), account: "A", now: now)
    #expect(scope.identityKey == DesktopReadScope.digest(Data(#"["chatgpt","A","U"]"#.utf8)))
    #expect(DesktopReadScope.localHostKey == "local:092af2cb59bdd804c6f7f1cd1d85464b682974e43cd517397d25510024034d1c")
    #expect(throws: DesktopFailure.self) { try DesktopReadScope.authenticated(principal(account: "B"), account: "A", now: now) }
    #expect(throws: DesktopFailure.self) { try DesktopReadScope.authenticated(principal(expiry: 99), account: "A", now: now) }
    #expect(throws: DesktopFailure.self) { try DesktopReadScope.authenticated(["authMethod": "apikey", "authToken": "invalid"], account: "A", now: now) }
}

@Test func recoveredUnreadNeverUnionsOtherUsersHostsOrLegacyMigration() throws {
    let first = UUID().uuidString, other = UUID().uuidString, legacy = UUID().uuidString
    let scope = DesktopReadScope(identityKey: "current")
    let state: [String: Any] = ["version": 1, "unreadByIdentity": [
        "current": [DesktopReadScope.localHostKey: [first, first], "durable:other": [other]],
        "different-user": [DesktopReadScope.localHostKey: [other]]],
        "legacyMigration": ["unreadThreadIdsByHostId": ["local": [legacy]]]]
    #expect(try scope.unread(in: state) == [first])
    #expect(try DesktopReadScope(identityKey: "missing").unread(in: state).isEmpty)
    #expect(throws: DesktopFailure.self) { try scope.unread(in: ["version": 2, "unreadByIdentity": [:]]) }
    #expect(throws: DesktopFailure.self) { try scope.unread(in: ["version": 1]) }
}

@Test func recoveryUsesLatestCompletedTurnAndNeverInventsLiveStateFromDisk() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE thread_turns (thread_id TEXT, rollout_ordinal INTEGER, status TEXT, completed_at INTEGER);
    INSERT INTO thread_turns VALUES ('done',1,'completed',1),('active',1,'completed',1),
    ('active',2,'inProgress',NULL),('failed',1,'failed',1),('stopped',1,'interrupted',1),
    ('incomplete',1,'completed',NULL),('read',1,'completed',1);
    """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    let source = StoredCompletions(path: path)
    #expect(try source.read(candidates: ["done", "active", "failed", "stopped", "incomplete", "missing"]) == ["done"])
    #expect(try source.read(candidates: []).isEmpty)
    #expect(sqlite3_exec(db, "UPDATE thread_turns SET status='inProgress',completed_at=NULL WHERE thread_id='done'", nil, nil, nil) == SQLITE_OK)
    #expect(try source.read(candidates: ["done"]).isEmpty)
}

@Test func restartRestoresUnreadWithoutLoadingAndLiveObservationTakesPrecedence() throws {
    let id = UUID().uuidString
    let restored = StoredCompletions.unloaded([id, "archived", "other-account"], eligible: [id], liveThreads: [])
    #expect(restored == [id])
    var presentation = DashboardPresentation()
    let snapshot = LiveSnapshot.session(initialized: true, observations: [], total: 1, unassigned: 0,
        restoredDone: restored.count, quota: [], quotaDate: Date(), accountFingerprint: "A")
    presentation.receive(snapshot)
    #expect(presentation.visibleSnapshot(at: snapshot.updatedAt)?.counts?.done == 1)
    #expect(snapshot.covered == 0) // Stored completion does not claim live runtime coverage.
    #expect(snapshot.lastCompleteSyncAt == nil)
    for (runtime, unread) in [("idle", true), ("idle", false), ("active", true)] {
        var stream = DesktopStream(conversationID: id, hostID: "local")
        let json = """
        {"type":"snapshot","revision":1,"conversationState":{"id":"\(id)","hostId":"local",
        "hasUnreadTurn":\(unread),"threadRuntimeStatus":{"type":"\(runtime)","activeFlags":[]},
        "requests":[],"turns":[{"turnId":"R","status":"completed"}]}}
        """
        let events = try stream.accept(change: JSONDecoder().decode(WireValue.self, from: Data(json.utf8)), owner: "owner")
        #expect(events.isEmpty) // Startup/reconnection baselines never replay alerts.
        let observation = try #require(stream.observation)
        #expect(StoredCompletions.unloaded(restored, eligible: [id], liveThreads: [id]).isEmpty)
        let live = LiveSnapshot.session(initialized: true, observations: [observation], total: 1, unassigned: 0,
            quota: [], quotaDate: Date(), accountFingerprint: "A")
        #expect(live.counts?.done == (runtime == "idle" && unread ? 1 : 0))
        #expect(live.counts?.processing == (runtime == "active" ? 1 : 0))
    }
}

@Test func readStoreChangesRemoveRecoveredUnreadWithoutOpeningAStream() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent(".codex-global-state.json"), id = UUID().uuidString
    let scope = DesktopReadScope(identityKey: "current")
    func write(_ unread: [String]) throws {
        let state: [String: Any] = ["electron-thread-read-state-v1": ["version": 1,
            "unreadByIdentity": ["current": [DesktopReadScope.localHostKey: unread]]]]
        try JSONSerialization.data(withJSONObject: state).write(to: file, options: .atomic)
    }
    try write([id])
    let watcher = try ReadStoreInvalidator(home: home)
    let initial = try watcher.read()
    #expect(initial.changed)
    #expect(try scope.unread(in: initial.state) == [id])
    #expect(try !watcher.read().changed)
    try write([])
    let updated = try watcher.read()
    #expect(updated.changed)
    #expect(try scope.unread(in: updated.state).isEmpty)
    #expect(try !watcher.read().changed)
}

@Test func readingLastRecoveredUnreadKeepsZeroCountsDuringOwnerDiscoveryGap() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let id = UUID().uuidString, scope = DesktopReadScope(identityKey: "current")
    let path = home.appendingPathComponent("history.sqlite").path
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, "CREATE TABLE thread_turns (thread_id TEXT,rollout_ordinal INTEGER,status TEXT,completed_at INTEGER)", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, "INSERT INTO thread_turns VALUES ('\(id)',1,'completed',1)", nil, nil, nil) == SQLITE_OK)
    let completions = StoredCompletions(path: path)
    func writeReadState(_ unread: Bool) throws {
        let state: [String: Any] = ["electron-thread-read-state-v1": ["version": 1,
            "unreadByIdentity": ["current": [DesktopReadScope.localHostKey: unread ? [id] : []]]]]
        try JSONSerialization.data(withJSONObject: state).write(to: home.appendingPathComponent(".codex-global-state.json"), options: .atomic)
    }
    try writeReadState(true)
    let watcher = try ReadStoreInvalidator(home: home)
    func snapshot() throws -> LiveSnapshot {
        let completed = try completions.read(candidates: [id])
        let unread = try scope.unread(in: watcher.read().state)
        let restored = StoredCompletions.unloaded(completed, eligible: [id], liveThreads: [])
        return LiveSnapshot.session(initialized: true, observations: [], total: 1, unassigned: 0,
            restoredDone: restored.intersection(unread).count, restoredCompleted: restored.count,
            quota: [], quotaDate: Date(), accountFingerprint: "A")
    }
    var presentation = DashboardPresentation()
    let before = try snapshot()
    presentation.receive(before)
    #expect(presentation.visibleSnapshot(at: before.updatedAt)?.counts == TaskCounts(done: 1))
    try writeReadState(false)
    #expect(try watcher.read().changed)
    let after = try snapshot()
    presentation.receive(after)
    #expect(presentation.visibleSnapshot(at: after.updatedAt)?.counts == TaskCounts())
    #expect(presentation.connectionLabel(at: after.updatedAt) == "Connected")
    #expect(after.covered == 0)
    #expect(after.restoredCompleted == 1)
    #expect(after.lastCompleteSyncAt == nil)

    // Cold startup with all results read must also show a valid zero baseline.
    var restart = DashboardPresentation()
    restart.receive(after)
    #expect(restart.visibleSnapshot(at: after.updatedAt)?.counts == TaskCounts())
    // A newly started turn invalidates that completed baseline. Never keep
    // cached zeroes merely because an earlier observation was completed.
    #expect(sqlite3_exec(db, "INSERT INTO thread_turns VALUES ('\(id)',2,'inProgress',NULL)", nil, nil, nil) == SQLITE_OK)
    let unavailable = try snapshot()
    presentation.receive(unavailable)
    #expect(presentation.visibleSnapshot(at: unavailable.updatedAt)?.counts == nil)
    #expect(unavailable.restoredCompleted == 0)
}

@Test func recoveredReadBaselineDoesNotOutliveConnectionOrAccountVerification() {
    var snapshot = LiveSnapshot.session(initialized: false, observations: [], total: 2, unassigned: 0,
        restoredCompleted: 2, quota: [], quotaDate: Date(), accountFingerprint: "A")
    #expect(snapshot.counts == nil)
    snapshot = LiveSnapshot.session(initialized: true, observations: [], total: 2, unassigned: 0,
        restoredCompleted: 2, quota: [], quotaDate: nil, accountFingerprint: "A")
    // Quota availability is independent of the already verified identity/IPC.
    #expect(snapshot.isConnected && snapshot.counts == TaskCounts())
    var presentation = DashboardPresentation()
    snapshot = LiveSnapshot.session(initialized: true, observations: [], total: 2, unassigned: 0,
        restoredCompleted: 2, quota: [], quotaDate: Date(), accountFingerprint: "A")
    presentation.receive(snapshot)
    #expect(presentation.visibleSnapshot(at: snapshot.updatedAt)?.counts == TaskCounts())
    var disconnected = LiveSnapshot()
    disconnected.accountFingerprint = "B"
    presentation.receive(disconnected)
    #expect(presentation.visibleSnapshot(at: disconnected.updatedAt) == nil)
}
