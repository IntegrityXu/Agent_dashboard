import Foundation
import Testing
import SQLite3
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private final class SessionClock { var now = 100.0 }
private final class SessionTransport: DesktopTransport {
    var hasPendingBytes: Bool { false }
    var hasPartialFrame: Bool { false }
    var sent: [[String: Any]] = []
    var incoming: [WireValue] = []
    var receives = 0
    var sendFailure: Error?
    var receiveFailure: Error?
    func send(_ message: [String: Any]) throws {
        if let sendFailure { throw sendFailure }; sent.append(message)
    }
    func receive(timeout: Int32) throws -> [WireValue] {
        receives += 1
        if let receiveFailure { throw receiveFailure }
        defer { incoming = [] }
        return incoming
    }
    var snapshotRequests: Int {
        sent.filter { $0["method"] as? String == "thread-stream-following-changed"
            && ($0["params"] as? [String: Any])?["following"] as? Bool == true }.count
    }
}
private struct UnusedSessionRPC: DesktopRPC {
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        throw DesktopFailure.unavailable
    }
}
private func sessionWire(_ value: [String: Any]) throws -> WireValue {
    try JSONDecoder().decode(WireValue.self, from: JSONSerialization.data(withJSONObject: value))
}

/// Real session coordinator and temporary stores, with deterministic time and
/// transport. No real Codex state, processes, sockets, or wall-clock sleeps.
private final class SessionPublications: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LiveSnapshot] = []
    func append(_ value: LiveSnapshot) { lock.withLock { values.append(value) } }
    var snapshots: [LiveSnapshot] { lock.withLock { values } }
}
private final class SessionFixture {
    let publications = SessionPublications()
    let home: URL
    let clock = SessionClock()
    let transport = SessionTransport()
    let session: DesktopSession
    let id = UUID().uuidString
    let scope = DesktopReadScope(identityKey: "fixture-user")
    init(rpc: any DesktopRPC = UnusedSessionRPC(), log: DiagnosticLog? = nil, codexBuild: String? = nil) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(home.appendingPathComponent("thread_history_1.sqlite").path, &db) == SQLITE_OK else {
            throw DesktopFailure.unavailable
        }
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE thread_turns(thread_id TEXT,rollout_ordinal INTEGER,status TEXT,completed_at INTEGER); INSERT INTO thread_turns VALUES ('\(id)',1,'completed',1);"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DesktopFailure.unavailable }
        let transport = transport, clock = clock, publications = publications
        session = try DesktopSession(home: home, rpc: rpc,
            identity: .init(id: "fixture", namespace: "fixture", readScope: scope),
            cancelled: { transport.receives > 0 }, refresh: { false }, publish: { publications.append($0) },
            transport: transport, uptime: { clock.now }, log: log, codexBuild: codexBuild, transportFactory: { transport })
        session.client = "observer"; session.ids = [id]; session.total = 1; session.quotaDate = Date()
        try writeUnread(false)
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    func writeUnread(_ unread: Bool) throws {
        let state: [String: Any] = ["electron-thread-read-state-v1": ["version": 1,
            "unreadByIdentity": [scope.identityKey: [DesktopReadScope.localHostKey: unread ? [id] : []]]]]
        try JSONSerialization.data(withJSONObject: state).write(to: home.appendingPathComponent(".codex-global-state.json"), options: .atomic)
    }
    func request() throws -> String {
        try session.request(id)
        return try #require(transport.sent.last?["requestId"] as? String)
    }
    func response(_ key: String, owner: String? = nil) throws -> WireValue {
        var value: [String: Any] = ["type": "response", "requestId": key,
            "resultType": owner == nil ? "error" : "success"]
        if let owner { value["handledByClientId"] = owner } else { value["error"] = "no-client-found" }
        return try sessionWire(value)
    }
    func owner(_ name: String = "owner") throws {
        let key = try request()
        try session.handle(response(key, owner: name))
    }
    func snapshot(_ unread: Bool, runtime: String = "idle", owner: String = "owner", revision: Int = 7, status: String = "completed") throws {
        try session.handle(sessionWire(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": owner, "params": ["hostId": "local", "conversationId": id,
                "change": ["type": "snapshot", "revision": revision, "conversationState": [
                    "id": id, "hostId": "local", "hasUnreadTurn": unread, "requests": [],
                    "threadRuntimeStatus": ["type": runtime, "activeFlags": []],
                    "turns": [["turnId": "R", "status": status]]]]]]))
    }
    func patch(_ revision: Int, _ patches: [[String: Any]]) throws {
        try session.handle(sessionWire(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": "owner", "params": ["hostId": "local", "conversationId": id,
                "change": ["type": "patches", "baseRevision": revision - 1, "revision": revision, "patches": patches]]]))
    }
    func tick() throws {
        session.nextIdentity = .greatestFiniteMagnitude; session.nextInventory = .greatestFiniteMagnitude
        session.nextOwners = .greatestFiniteMagnitude; session.nextQuota = .greatestFiniteMagnitude
        session.nextStoredUnread = .greatestFiniteMagnitude
        transport.receives = 0
        try session.run()
    }
    var snapshot: LiveSnapshot { session.snapshot() }
}

@Test func ownerDiscoveryAllowsRouterDeadlineBeforeDiscardingRecoveredDone() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    let key = try f.request()
    #expect(try #require(f.session.requests[key]).deadline >= f.clock.now + 13)
    f.clock.now += 6
    try f.tick()
    #expect(f.session.requests[key] != nil)
    #expect(f.snapshot.counts?.done == 1)
    f.clock.now += 4
    try f.session.handle(f.response(key))
    #expect(f.session.requests[key] == nil)
    #expect(f.snapshot.counts?.done == 1)
}

@Test func initialInventoryDiscoversRecentActivityBeforeOldUUIDs() throws {
    let f = try SessionFixture()
    let old = "00000000-0000-0000-0000-000000000001"
    let recent = "ffffffff-ffff-ffff-ffff-ffffffffffff"
    var db: OpaquePointer?
    #expect(sqlite3_open(f.home.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE threads(id TEXT, creator_account_id TEXT, source TEXT, archived INTEGER, recency_at_ms INTEGER, updated_at INTEGER);
    CREATE TABLE thread_spawn_edges(child_thread_id TEXT);
    INSERT INTO threads VALUES ('\(old)','fixture','cli',0,1,1);
    INSERT INTO threads VALUES ('\(recent)','fixture','cli',0,2,2);
    """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    f.session.ids = []
    try f.session.refreshInventory()
    #expect(f.session.total == 2)
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: []) == recent)
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: []) == old)
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: []) == nil)
}

@Test func orderedDiscoveryDeduplicatesWithoutReplacingUnfinishedTail() {
    var queue = DiscoveryQueue()
    queue.enqueueOrdered(["recent", "older", "oldest", "recent"])
    let eligible: Set<String> = ["recent", "older", "oldest", "new"]
    #expect(queue.next(eligible: eligible, pending: []) == "recent")
    queue.enqueueOrdered(["new", "recent", "older"])
    #expect(queue.next(eligible: eligible, pending: []) == "older")
    #expect(queue.next(eligible: eligible, pending: []) == "oldest")
    #expect(queue.next(eligible: eligible, pending: []) == "new")
    #expect(queue.next(eligible: eligible, pending: ["recent"]) == nil)
}

@Test func protocolCheckRejectsUnverifiedStreamVersions() throws {
    let f = try SessionFixture()
    try f.owner()
    try f.snapshot(false, runtime: "active", status: "inProgress")
    #expect(f.snapshot.counts?.processing == 1)
    do {
        try f.session.handle(sessionWire(["type": "broadcast", "method": "thread-stream-state-changed", "version": 12,
            "sourceClientId": "owner", "params": ["hostId": "local", "conversationId": f.id,
                "change": ["type": "patches", "baseRevision": 7, "revision": 8, "patches": []]]]))
    }
    #expect(f.snapshot.isConnected)
    #expect(f.session.threads.observations[f.id] == nil)
    #expect(f.session.threads.recoveryBlocked.contains(f.id))
}

@Test func activeConversationHintsUseReservedDiscoverySlotsWithoutDroppingBackgroundWork() throws {
    let f = try SessionFixture()
    let background = (0..<10).map { "old-\($0)" }
    let active = ["new-a", "new-b", "new-c"]
    f.session.ids = Set(background + active)
    f.session.discovery.enqueueOrdered(background)
    try f.session.discoverOwners()
    #expect(f.session.requests.count == 6)
    f.session.discovery.prioritize(active + ["new-a"])
    try f.session.discoverOwners()
    #expect(f.session.requests.count == 8)
    #expect(Set(f.session.requests.values.compactMap(\.thread)).isSuperset(of: ["new-a", "new-b"]))
    let first = try #require(f.session.requests.first { $0.value.thread == "old-0" }?.key)
    try f.session.handle(f.response(first))
    try f.session.discoverOwners()
    #expect(f.session.requests.values.contains { $0.thread == "new-c" })
    for id in background.dropFirst(6) {
        #expect(f.session.discovery.next(eligible: f.session.ids, pending: []) == id)
    }
}

@Test func renewedAndNewInventoryActivityBypassesAnUnfinishedHistoricalScan() throws {
    let f = try SessionFixture()
    let existing = UUID().uuidString, new = UUID().uuidString
    var db: OpaquePointer?
    #expect(sqlite3_open(f.home.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, """
        CREATE TABLE threads(id TEXT, creator_account_id TEXT, source TEXT, archived INTEGER, recency_at_ms INTEGER, updated_at INTEGER);
        CREATE TABLE thread_spawn_edges(child_thread_id TEXT);
        INSERT INTO threads VALUES ('\(existing)','fixture','cli',0,1,1);
        """, nil, nil, nil) == SQLITE_OK)
    f.session.ids = []
    try f.session.refreshInventory()
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: []) == existing)
    f.session.discovery.enqueueOrdered(["old-history"])
    #expect(sqlite3_exec(db, """
        UPDATE threads SET recency_at_ms=2 WHERE id='\(existing)';
        INSERT INTO threads VALUES ('\(new)','fixture','cli',0,3,3);
        """, nil, nil, nil) == SQLITE_OK)
    try f.session.refreshInventory()
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: [], allowBackground: false) == new)
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: [], allowBackground: false) == existing)
    try f.session.refreshInventory() // Unchanged metadata must not repeat urgent work.
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: [], allowBackground: false) == nil)
    #expect(f.session.discovery.next(eligible: ["old-history"], pending: []) == "old-history")
}

private func followingHint(_ id: String, host: String = "local", version: Int = 1, sender: String = "candidate") throws -> WireValue {
    try sessionWire(["type": "broadcast", "method": "thread-stream-following-status-requested", "version": version,
        "sourceClientId": sender, "params": ["hostId": host, "conversationId": id]])
}

@Test func ownerAnnouncementIsOnlyAHintAndCannotBypassScopeOrOwnerVerification() throws {
    let f = try SessionFixture()
    try f.session.handle(followingHint(f.id, host: "remote"))
    try f.session.handle(followingHint(f.id, version: 2))
    #expect(f.session.discovery.next(eligible: f.session.ids, pending: [], allowBackground: false) == nil)
    f.session.nextInventory = 200
    try f.session.handle(followingHint("other-account"))
    #expect(f.session.nextInventory == 0)
    try f.session.discoverOwners()
    #expect(f.session.requests.isEmpty && f.session.threads.owners.isEmpty)
    try f.session.handle(followingHint(f.id))
    try f.session.discoverOwners()
    #expect(f.session.requests.count == 1)
    #expect(f.session.threads.owners.isEmpty && f.snapshot.covered == 0)
    let key = try #require(f.session.requests.first?.key)
    try f.session.handle(f.response(key, owner: "verified-owner"))
    #expect(f.session.threads.owners[f.id] == "verified-owner")
    try f.snapshot(false, owner: "verified-owner")
    let sent = f.transport.snapshotRequests
    try f.session.handle(followingHint(f.id, sender: "verified-owner"))
    #expect(f.transport.snapshotRequests == sent + 1)
}

@MainActor private final class MultiThreadPlayback: AlertPlayback {
    var played: [AlertKind] = []
    var finished: (@MainActor () -> Void)?
    func play(_ kind: AlertKind, completion: @escaping @MainActor () -> Void) -> Bool {
        played.append(kind); finished = completion; return true
    }
    func stop() { finished = nil }
}

@Test @MainActor func secondConversationCountsAndCanonicalWaitingCompletionReachPlayback() throws {
    let f = try SessionFixture(), other = UUID().uuidString
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    f.session.ids.insert(other); f.session.total = 2
    try f.session.handle(followingHint(other)); try f.session.discoverOwners()
    let key = try #require(f.session.requests.first { $0.value.thread == other }?.key)
    try f.session.handle(f.response(key, owner: "other-owner"))
    func change(_ payload: [String: Any]) throws {
        try f.session.handle(sessionWire(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": "other-owner", "params": ["hostId": "local", "conversationId": other, "change": payload]]))
    }
    try change(["type": "snapshot", "revision": 1, "conversationState": ["id": other, "hostId": "local",
        "hasUnreadTurn": false, "requests": [], "turns": [], "threadRuntimeStatus": ["type": "active", "activeFlags": []],
        "turnHistory": ["kind": "canonical", "history": ["entitiesByKey": ["R2": ["turnId": "R2", "status": "inProgress", "items": []]],
            "islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "R2"]]]]]]]])
    #expect(f.snapshot.counts?.processing == 2)
    let items: [Any] = ["turnHistory", "history", "entitiesByKey", "R2", "items"]
    try change(["type": "patches", "baseRevision": 1, "revision": 2, "patches": [
        ["op": "add", "path": items + [0], "value": ["type": "agentMessage", "id": "Q", "questions": [["title": "fixture"]]]]]])
    #expect(f.snapshot.counts?.processing == 1 && f.snapshot.counts?.waiting == 1)
    try change(["type": "patches", "baseRevision": 2, "revision": 3, "patches": [
        ["op": "replace", "path": items + [0, "questions"], "value": []]]])
    #expect(f.snapshot.counts?.processing == 2 && f.snapshot.counts?.waiting == 0)
    try change(["type": "patches", "baseRevision": 3, "revision": 4, "patches": [
        ["op": "replace", "path": ["turnHistory", "history", "entitiesByKey", "R2", "status"], "value": "completed"],
        ["op": "replace", "path": ["threadRuntimeStatus", "type"], "value": "idle"],
        ["op": "replace", "path": ["hasUnreadTurn"], "value": true]]])
    #expect(f.snapshot.counts?.processing == 1 && f.snapshot.counts?.done == 1)
    let player = MultiThreadPlayback()
    let notifications = AudioNotifications(playback: player)
    for snapshot in f.publications.snapshots { notifications.receive(snapshot) }
    #expect(player.played == [.waiting])
    player.finished?()
    #expect(player.played == [.waiting, .completed])
    #expect(f.publications.snapshots.flatMap(\.audioEvents).allSatisfy { $0.thread == other })
}

@Test func bufferedOwnerResponseIsHandledBeforeTimeoutCleanup() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    let key = try f.request()
    f.clock.now = try #require(f.session.requests[key]).deadline + 1
    f.transport.incoming = [try f.response(key, owner: "owner")]
    try f.tick()
    #expect(f.session.threads.owners[f.id] == "owner")
    try f.snapshot(true)
    #expect(f.snapshot.counts?.done == 1)
}

@Test func lateOwnerResponseAfterTimeoutCanStillEstablishASilentBaseline() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    let key = try f.request()
    f.clock.now = try #require(f.session.requests[key]).deadline + 1
    try f.tick()
    #expect(f.session.requests[key] == nil)
    #expect(f.snapshot.counts?.done == 1) // Never loaded: keep verified disk coverage.
    try f.session.handle(f.response(key, owner: "owner"))
    #expect(f.session.threads.owners[f.id] == "owner")
    #expect(f.snapshot.counts == nil) // Once live, old disk evidence cannot override it.
    try f.snapshot(true)
    #expect(f.snapshot.counts?.done == 1)
}

@Test func lateRepliesCannotOverrideNewDiscoveryOrRemovedThreads() throws {
    let f = try SessionFixture()
    let old = try f.request()
    f.clock.now = try #require(f.session.requests[old]).deadline + 1
    try f.tick()
    let new = try f.request()
    try f.session.handle(f.response(old, owner: "stale-owner"))
    #expect(f.session.threads.owners.isEmpty)
    try f.session.handle(f.response(new, owner: "new-owner"))
    #expect(f.session.threads.owners[f.id] == "new-owner")
    let removed = try f.request()
    try f.session.removeThread(f.id, reason: .unloaded)
    f.session.ids = []
    try f.session.handle(f.response(removed, owner: "removed-owner"))
    #expect(f.session.threads.owners.isEmpty)
}

@Test func timeoutOfKnownLiveThreadStillBlocksOlderDiskCompletion() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    try f.owner(); try f.snapshot(true, runtime: "active")
    #expect(f.snapshot.counts?.processing == 1)
    let key = try f.request()
    f.clock.now = try #require(f.session.requests[key]).deadline + 1
    try f.tick()
    #expect(f.snapshot.counts == nil)
    #expect(f.session.threads.recoveryBlocked.contains(f.id))
}

@Test func readChangesDuringInflightSnapshotAlwaysReceiveAFollowup() throws {
    for initiallyUnread in [false, true] {
        let f = try SessionFixture()
        try f.writeUnread(initiallyUnread); try f.session.refreshRecovery()
        try f.owner(); try f.snapshot(initiallyUnread)
        try f.session.follow(f.id, true)
        let deadline = f.session.threads.snapshotDeadlines[f.id]
        let before = f.transport.snapshotRequests
        try f.writeUnread(!initiallyUnread); try f.session.refreshRecovery()
        #expect(f.transport.snapshotRequests == before)
        #expect(f.session.threads.snapshotDeadlines[f.id] == deadline)
        try f.snapshot(initiallyUnread) // Old, same-revision response arrives late.
        #expect(f.transport.snapshotRequests == before + 1)
        #expect(f.session.threads.snapshotDeadlines[f.id] != nil)
        try f.snapshot(!initiallyUnread)
        #expect(f.snapshot.counts?.done == (initiallyUnread ? 0 : 1))
        #expect(f.snapshot.isConnected)
        #expect(f.session.threads.snapshotDeadlines[f.id] == nil)
        #expect(f.transport.snapshotRequests == before + 1)
    }
}

@Test func multipleReadChangesCoalesceAndOwnerReplacementClearsOldRefresh() throws {
    let f = try SessionFixture()
    try f.session.refreshRecovery(); try f.owner(); try f.snapshot(false)
    try f.session.follow(f.id, true)
    let before = f.transport.snapshotRequests
    for unread in [true, false, true] { try f.writeUnread(unread); try f.session.refreshRecovery() }
    try f.snapshot(false)
    #expect(f.transport.snapshotRequests == before + 1)
    try f.snapshot(true)
    #expect(f.snapshot.counts?.done == 1)
    try f.session.follow(f.id, true)
    try f.writeUnread(false); try f.session.refreshRecovery()
    try f.owner("replacement")
    let replaced = f.transport.snapshotRequests
    try f.snapshot(true, owner: "owner") // Previous owner cannot satisfy new request.
    #expect(f.session.threads.snapshotDeadlines[f.id] != nil)
    try f.snapshot(false, owner: "replacement")
    #expect(f.transport.snapshotRequests == replaced)
    #expect(f.snapshot.counts?.done == 0)
}

@Test func lateNoOwnerReplyRestoresCoverageAfterKnownOwnerTimeout() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    try f.owner(); try f.snapshot(true)
    let key = try f.request()
    f.clock.now = try #require(f.session.requests[key]).deadline + 1
    try f.session.expireRequests()
    #expect(f.snapshot.counts == nil)
    try f.session.handle(f.response(key))
    #expect(f.snapshot.counts?.done == 1)
    #expect(f.session.threads.recoveryBlocked.isEmpty)
}

@Test func lateReplyRetentionIsBounded() throws {
    let f = try SessionFixture()
    let key = try f.request()
    f.clock.now = try #require(f.session.requests[key]).deadline + 1
    try f.session.expireRequests()
    #expect(f.session.lateRequests.count == 1)
    f.clock.now += 31
    // The response handler must enforce expiry even before the next timer pass.
    try f.session.handle(f.response(key, owner: "too-late"))
    #expect(f.session.threads.owners.isEmpty)
    #expect(f.session.lateRequests.isEmpty)
}

@Test func staleSnapshotDoesNotConsumeDirtyRefreshAndTimeoutClearsIt() throws {
    let f = try SessionFixture()
    try f.session.refreshRecovery(); try f.owner(); try f.snapshot(false)
    try f.session.follow(f.id, true)
    let deadline = try #require(f.session.threads.snapshotDeadlines[f.id])
    try f.writeUnread(true); try f.session.refreshRecovery()
    let before = f.transport.snapshotRequests
    try f.snapshot(false, revision: 6) // Older than the accepted revision 7.
    #expect(f.session.threads.snapshotDeadlines[f.id] == deadline)
    #expect(f.transport.snapshotRequests == before)
    f.clock.now = deadline + 1
    try f.session.expireRequests()
    #expect(f.session.threads.owners.isEmpty)
    try f.owner("replacement")
    let replaced = f.transport.snapshotRequests
    try f.snapshot(true, owner: "replacement")
    #expect(f.snapshot.counts?.done == 1)
    #expect(f.session.threads.snapshotDeadlines.isEmpty)
    #expect(f.transport.snapshotRequests == replaced)
}

@Test func sessionDeliversLiveAlertsOnceAndRecoveryNeverCreatesAlerts() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery(); f.session.emit()
    #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    let wait: [[String: Any]] = [["op": "add", "path": ["requests", 0], "value": [
        "id": 1, "method": "item/tool/requestUserInput", "params": ["turnId": "R"]]]]
    try f.patch(8, wait)
    try f.patch(9, [["op": "replace", "path": ["requests"], "value": []]])
    let complete: [[String: Any]] = [["op": "replace", "path": ["turns", 0, "status"], "value": "completed"]]
    try f.patch(10, complete); try f.patch(10, complete)
    f.session.emit(); f.session.emit()
    let events = f.publications.snapshots.flatMap(\.audioEvents)
    #expect(events.map(\.transition.kind) == [.waiting, .completed])
    #expect(events.allSatisfy { $0.thread == f.id })
    #expect(f.snapshot.audioEvents.isEmpty) // Publication drains the event batch.
    #expect(f.snapshot.counts?.done == 0) // Already-read completion still alerts.
    try f.session.refreshRecovery(); f.session.emit()
    #expect(f.publications.snapshots.flatMap(\.audioEvents).count == 2)
}

@Test func sourceGapPublishesCancellationAndResnapshotIsSilent() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.patch(9, []) // Missing revision 8: invalidate and request new snapshot.
    #expect(f.publications.snapshots.last?.invalidatedAudioThreads == [f.id])
    #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
    try f.snapshot(true, revision: 10)
    f.session.emit()
    #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
    #expect(f.snapshot.counts?.done == 1)
}

@Test func eventsBeforeSessionReadinessAreNotBufferedForLaterSound() throws {
    let f = try SessionFixture()
    f.session.identityVerified = false
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.patch(8, [["op": "replace", "path": ["turns", 0, "status"], "value": "completed"]])
    f.session.identityVerified = true; f.session.emit()
    #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
}

@Test func childSubscriptionsDoNotChangeCountsOrAudioAndEndWithParent() throws {
    let f = try SessionFixture(), child = UUID().uuidString
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.patch(8, [["op": "add", "path": ["turns", 0, "items"], "value": [[
        "id": "spawn", "type": "subAgentActivity", "kind": "started", "agentThreadId": child, "agentPath": "/root/reviewer"]]]])
    try f.session.refreshAgents()
    #expect(f.session.agentIDs == [child])
    try f.session.request(child)
    let key = try #require(f.transport.sent.last?["requestId"] as? String)
    try f.session.handle(f.response(key, owner: "child-owner"))
    #expect(f.session.threads.owners[child] == "child-owner")
    try f.session.handle(sessionWire(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
        "sourceClientId": "child-owner", "params": ["hostId": "local", "conversationId": child,
            "change": ["type": "snapshot", "revision": 1, "conversationState": [
                "id": child, "hostId": "local", "hasUnreadTurn": false, "requests": [],
                "threadRuntimeStatus": ["type": "active", "activeFlags": []],
                "turns": [["turnId": "child-run", "status": "inProgress"]]]]]]))
    #expect(f.snapshot.counts?.processing == 1)
    #expect(f.snapshot.covered == 1 && f.snapshot.total == 1)
    #expect(f.snapshot.agents.map(\.label) == ["root.....", "reviewer....."])
    try f.session.handle(sessionWire(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
        "sourceClientId": "child-owner", "params": ["hostId": "local", "conversationId": child,
            "change": ["type": "patches", "baseRevision": 1, "revision": 2, "patches": [
                ["op": "replace", "path": ["turns", 0, "status"], "value": "completed"]]]]]))
    #expect(f.snapshot.agents.map(\.label) == ["root.....", "reviewer done"])
    #expect(f.snapshot.counts?.done == 0)
    #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
    try f.patch(9, [["op": "replace", "path": ["turns", 0, "status"], "value": "completed"]])
    try f.session.refreshAgents()
    #expect(f.snapshot.agents.isEmpty)
    #expect(f.session.agentIDs.isEmpty && f.session.threads.owners[child] == nil)
    #expect(f.publications.snapshots.flatMap(\.audioEvents).map(\.thread) == [f.id])
}

@Test func sessionPublishesLatestCompactStatusIndependentlyOfAudio() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.patch(8, [["op": "replace", "path": ["threadRuntimeStatus", "activeFlags"], "value": ["waitingOnUserInput"]]])
    #expect(f.snapshot.compactStatus == .waiting)
    try f.patch(9, [["op": "replace", "path": ["threadRuntimeStatus", "activeFlags"], "value": []]])
    #expect(f.snapshot.compactStatus == nil)
    // Heartbeat completion is intentionally silent, but still needs a badge.
    try f.patch(10, [["op": "add", "path": ["turns", 0, "automationKind"], "value": "heartbeat"],
                    ["op": "replace", "path": ["turns", 0, "status"], "value": "completed"],
                    ["op": "replace", "path": ["threadRuntimeStatus", "type"], "value": "idle"],
                    ["op": "replace", "path": ["hasUnreadTurn"], "value": true]])
    #expect(f.snapshot.compactStatus == .done)
    #expect(f.publications.snapshots.flatMap(\.audioEvents).map(\.transition.kind) == [.waiting])
    try f.patch(11, [["op": "replace", "path": ["hasUnreadTurn"], "value": false]])
    #expect(f.snapshot.compactStatus == nil)
}


private final class RecoveringRPC: DesktopRPC {
    var failure: Error? = RPCFailure.timeout
    var account = "fixture"
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        if let failure { throw failure }
        return ["accountId": account, "rateLimits": ["secondary": ["usedPercent": 40.0, "windowDurationMins": 10080] as [String: Any]]]
    }
}

@Test func quotaTimeoutPreservesLiveCountsAndRecoversWithoutNewHandshake() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    let originalDate = f.session.quotaDate
    try f.session.refreshQuota()
    #expect(f.snapshot.isConnected && f.snapshot.counts?.processing == 1)
    #expect(f.session.quotaDate == originalDate)
    #expect(f.session.sourceFailures.failures[.quota]?.attempts == 1)
    rpc.failure = nil
    try f.session.refreshQuota()
    #expect(f.session.sourceFailures.failures[.quota] == nil)
    #expect(f.snapshot.quota.first?.remaining == 60)
    #expect(!f.transport.sent.contains { $0["method"] as? String == "initialize" })
}

@Test func malformedReadStoreDropsOnlyRecoveredCountsAndRestoresSilently() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    #expect(f.snapshot.counts?.done == 1)
    try Data("incomplete JSON".utf8).write(to: f.home.appendingPathComponent(".codex-global-state.json"))
    try f.session.refreshRecovery()
    #expect(f.snapshot.isConnected)
    #expect(f.snapshot.restoredDone == 0 && f.snapshot.restoredCompleted == 0)
    #expect(f.session.sourceFailures.failures[.readStore] != nil)
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    #expect(f.snapshot.counts?.processing == 1)
    try f.writeUnread(true); try f.session.refreshRecovery()
    #expect(f.session.sourceFailures.failures[.readStore] == nil)
    #expect(f.snapshot.audioEvents.isEmpty)
}

@Test func historyReadFailureDoesNotConsumeReadInvalidation() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(true)
    try f.writeUnread(false)
    let path = f.home.appendingPathComponent("thread_history_1.sqlite")
    let backup = path.appendingPathExtension("backup")
    try FileManager.default.moveItem(at: path, to: backup)
    try f.session.refreshRecovery()
    #expect(f.snapshot.isConnected && f.session.sourceFailures.failures[.completions] != nil)
    #expect(f.session.invalidator?.previous == nil)
    try FileManager.default.moveItem(at: backup, to: path)
    let before = f.transport.snapshotRequests
    try f.session.refreshRecovery()
    #expect(f.transport.snapshotRequests == before + 1)
    #expect(f.session.sourceFailures.failures[.completions] == nil)
}

@Test func inventoryFailureHasBoundedGraceAndDoesNotDisconnect() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.session.refreshInventory() // Fixture intentionally has no inventory database.
    #expect(f.snapshot.counts?.processing == 1)
    f.clock.now += 31
    #expect(f.snapshot.isConnected && f.snapshot.counts == nil && f.snapshot.agents.isEmpty)
    try f.session.applyInventory(Inventory(ids: [f.id], activity: [:], total: 1, unassigned: 0))
    f.session.sourceFailures.recovered(.inventory, now: f.clock.now, log: nil)
    #expect(f.snapshot.counts?.processing == 1)
}

@Test func identityReadTimeoutKeepsSocketButHidesUnverifiedData() throws {
    let f = try SessionFixture(rpc: RecoveringRPC())
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.session.refreshIdentity()
    #expect(f.session.client == "observer" && f.session.threads.owners[f.id] != nil)
    #expect(f.snapshot.accountFingerprint == nil && f.snapshot.counts == nil && f.snapshot.quota.isEmpty)
    f.clock.now += 31
    #expect(throws: (any Error).self) { try f.session.refreshIdentity() }
}

@Test func closedHelperAndChangedQuotaAccountStillRequireReconnection() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    rpc.failure = RPCFailure.closed
    #expect(throws: (any Error).self) { try f.session.refreshQuota() }
    rpc.failure = nil; rpc.account = "different-account"
    #expect(throws: DesktopFailure.identityChanged) { try f.session.refreshQuota() }
}

@Test func diagnosticsRecordStageRecoveryAndRotateWithoutSensitiveDescriptions() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("diagnostics.jsonl")
    let log = DiagnosticLog(url: url, limit: 1024)
    var failures = SourceFailures()
    let secret = "SECRET_TOKEN_AND_CONVERSATION"
    let error = NSError(domain: secret, code: 7, userInfo: [NSLocalizedDescriptionKey: secret])
    failures.failed(.readStore, error: error, now: 0, log: log)
    failures.recovered(.readStore, now: 5, log: log)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("readStore") && text.contains("recovered") && text.contains("io_error_7"))
    #expect(!text.contains(secret))
    for _ in 0..<20 { log.record(.socket, event: "session_reconnect", error: RPCFailure.closed) }
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("1").path))
    for file in [url, url.appendingPathExtension("1")] {
        let data = try Data(contentsOf: file)
        #expect(data.count <= 1024)
        for row in data.split(separator: 10) { _ = try JSONSerialization.jsonObject(with: Data(row)) }
    }
}


@Test func sessionLoopSurvivesQuotaAndRecoveryFailuresAndKeepsSubscriptions() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try Data("partial JSON".utf8).write(to: f.home.appendingPathComponent(".codex-global-state.json"))
    f.session.nextIdentity = .greatestFiniteMagnitude
    f.session.nextInventory = .greatestFiniteMagnitude
    f.session.nextOwners = .greatestFiniteMagnitude
    try f.session.run()
    #expect(f.session.threads.owners[f.id] == "owner")
    #expect(f.snapshot.isConnected && f.snapshot.counts?.processing == 1)
    #expect(f.session.sourceFailures.failures[.quota] != nil)
    #expect(f.session.sourceFailures.failures[.readStore] != nil)
}


@Test func actualSocketFailureReconnectsOnlyRealtimeChannel() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    rpc.failure = nil
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    f.transport.receiveFailure = DesktopFailure.unavailable
    try f.tick()
    try f.session.refreshQuota()
    #expect(f.session.socket == nil && f.session.client == "initializing-client")
    #expect(f.snapshot.isConnected && f.snapshot.counts == nil)
    #expect(f.snapshot.quota.first?.remaining == 60)
    #expect(f.snapshot.features[.tasks]?.state == .unavailable)
    #expect(f.snapshot.features[.quota]?.state == .available)
    #expect(f.session.threads.recoveryBlocked.contains(f.id))
}

@Test func newBuildWithCompatibleDataKeepsCountsAndQuotaAvailable() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc, codexBuild: "99999.1")
    rpc.failure = nil
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.session.refreshQuota()
    #expect(f.snapshot.codexBuild == "99999.1")
    #expect(f.snapshot.counts?.processing == 1 && f.snapshot.quota.first?.remaining == 60)
    #expect(f.snapshot.compatibilityIssue == nil)
    #expect(f.snapshot.features[.tasks]?.state == .available)
}

@Test func additiveFieldsDoNotInterruptValidatedStatusOrRevisionContinuity() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.patch(8, [["op": "add", "path": ["futureOptionalField"], "value": ["anything": 42]]])
    #expect(f.snapshot.counts?.processing == 1 && f.session.streamIssues.isEmpty)
    try f.patch(9, [["op": "replace", "path": ["threadRuntimeStatus", "type"], "value": "idle"],
        ["op": "replace", "path": ["turns", 0, "status"], "value": "completed"],
        ["op": "replace", "path": ["hasUnreadTurn"], "value": true]])
    #expect(f.snapshot.counts?.done == 1)
    #expect(f.publications.snapshots.flatMap(\.audioEvents).count == 1)
}

@Test func missingFieldsAndUnknownStatesDisableOnlyAffectedConversationAndRecoverSilently() throws {
    let changes: [[String: Any]] = [
        ["op": "remove", "path": ["requests"]],
        ["op": "remove", "path": ["hasUnreadTurn"]],
        ["op": "remove", "path": ["threadRuntimeStatus"]],
        ["op": "remove", "path": ["turns"]],
        ["op": "remove", "path": ["turns", 0, "status"]],
        ["op": "remove", "path": ["threadRuntimeStatus", "activeFlags"]],
        ["op": "replace", "path": ["threadRuntimeStatus", "type"], "value": "future-state"],
        ["op": "replace", "path": ["threadRuntimeStatus", "activeFlags"], "value": ["future-flag"]],
        ["op": "replace", "path": ["turns", 0, "status"], "value": "future-status"]]
    for change in changes {
        let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
        rpc.failure = nil
        try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
        try f.session.refreshQuota()
        try f.patch(8, [change])
        #expect(f.snapshot.counts == nil)
        #expect(f.snapshot.quota.first?.remaining == 60 && f.snapshot.isConnected)
        #expect(f.snapshot.features[.tasks]?.state == .incompatible)
        #expect(f.session.threads.recoveryBlocked.contains(f.id))
        #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
        try f.snapshot(true, revision: 9)
        #expect(f.snapshot.features[.tasks]?.state == .available && f.snapshot.counts?.done == 1)
        #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
    }
}

@Test func incompatibleHistoryAndQuotaDoNotInterruptValidLiveTasks() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    rpc.failure = nil
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.session.refreshQuota()
    try JSONSerialization.data(withJSONObject: ["electron-thread-read-state-v1": ["version": 2]])
        .write(to: f.home.appendingPathComponent(".codex-global-state.json"))
    try f.session.refreshRecovery()
    rpc.failure = DesktopFailure.unsupported
    try f.session.refreshQuota()
    #expect(f.snapshot.counts?.processing == 1)
    #expect(f.snapshot.features[.history]?.state == .incompatible)
    #expect(f.snapshot.features[.quota]?.state == .saved)
    #expect(f.snapshot.features[.tasks]?.state == .available)
    var presentation = DashboardPresentation()
    presentation.receive(f.snapshot)
    #expect(presentation.connectionLabel(at: Date()) == "Connected · Limited")
    #expect(presentation.windows(at: Date()).first?.remaining == 60)
    rpc.failure = nil
    try f.writeUnread(false); try f.session.refreshRecovery(); try f.session.refreshQuota()
    #expect(f.snapshot.features[.history]?.state == .available)
    #expect(f.snapshot.features[.quota]?.state == .available)
}

@Test func incompatibleInventoryImmediatelyHidesCountsButKeepsUsage() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    rpc.failure = nil
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    try f.session.refreshQuota()
    var db: OpaquePointer?
    #expect(sqlite3_open(f.home.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
    sqlite3_close(db) // Existing database with an incompatible schema.
    try f.session.refreshInventory()
    #expect(f.snapshot.counts == nil && f.snapshot.audioEvents.isEmpty)
    #expect(f.snapshot.features[.tasks]?.state == .incompatible)
    #expect(f.snapshot.features[.quota]?.state == .available)
}

@Test func failedHandshakeCanRecoverWithoutReplacingQuotaSession() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    rpc.failure = nil; try f.session.refreshQuota()
    f.session.client = "initializing-client"
    try f.session.request(nil)
    let key = try #require(f.transport.sent.last?["requestId"] as? String)
    f.transport.incoming = [try sessionWire(["type": "response", "requestId": key, "resultType": "success", "result": [:]])]
    f.session.pollRealtime()
    #expect(f.session.socket == nil)
    #expect(f.snapshot.features[.tasks]?.state == .incompatible)
    #expect(f.snapshot.quota.first?.remaining == 60)
    f.clock.now += 31; f.transport.receives = 0
    f.session.pollRealtime()
    let retry = try #require(f.transport.sent.last?["requestId"] as? String)
    #expect(retry != key)
    try f.session.handle(sessionWire(["type": "response", "requestId": retry, "resultType": "success", "result": ["clientId": "new-observer", "extra": true]]))
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    #expect(f.snapshot.features[.tasks]?.state == .available)
    #expect(f.snapshot.counts?.processing == 1 && f.snapshot.quota.first?.remaining == 60)
    #expect(f.publications.snapshots.flatMap(\.audioEvents).isEmpty)
}

@Test func socketSendFailureInvalidatesLiveCountsAndDoesNotEscape() throws {
    let rpc = RecoveringRPC(), f = try SessionFixture(rpc: rpc)
    rpc.failure = nil; try f.session.refreshQuota()
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    f.transport.sendFailure = DesktopFailure.unavailable
    try f.session.follow(f.id, true)
    #expect(f.session.socket == nil && f.session.threads.snapshotDeadlines.isEmpty)
    #expect(f.snapshot.counts == nil && f.snapshot.quota.first?.remaining == 60)
}

@Test func idleRuntimeWithoutActiveFlagsRemainsCompatible() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(true)
    try f.patch(8, [["op": "remove", "path": ["threadRuntimeStatus", "activeFlags"]]])
    #expect(f.snapshot.counts?.done == 1)
    #expect(f.snapshot.features[.tasks]?.state == .available)
}

@Test func unsupportedDiscoveryProtocolDoesNotMasqueradeAsUnloadedHistory() throws {
    let f = try SessionFixture()
    try f.writeUnread(true); try f.session.refreshRecovery()
    let key = try f.request()
    try f.session.handle(sessionWire(["type": "response", "requestId": key,
        "resultType": "error", "error": "unsupported-version"]))
    #expect(f.snapshot.counts == nil && f.snapshot.features[.tasks]?.state == .incompatible)
    #expect(f.session.threads.recoveryBlocked.contains(f.id))
}

private final class StartupQuotaRPC: DesktopRPC {
    var didRead = false
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        #expect(method == "account/rateLimits/read")
        didRead = true
        return ["accountId": "fixture", "rateLimits": ["primary": ["usedPercent": 20, "windowDurationMins": 300]]]
    }
}

@Test func missingSocketAndReadWatcherAtStartupStillAllowFreshQuota() throws {
    let rpc = StartupQuotaRPC()
    let missingHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let session = try DesktopSession(home: missingHome, rpc: rpc,
        identity: .init(id: "fixture", namespace: "fixture", readScope: .init(identityKey: "user")),
        cancelled: { rpc.didRead }, refresh: { false }, publish: { _ in },
        transportFactory: { throw DesktopFailure.unavailable })
    try session.run()
    let snapshot = session.snapshot()
    #expect(snapshot.isConnected && snapshot.quota.first?.remaining == 80)
    #expect(snapshot.counts == nil && snapshot.features[.tasks]?.state == .unavailable)
    #expect(snapshot.features[.quota]?.state == .available)
    #expect(session.invalidator == nil && snapshot.features[.history]?.isDegraded == true)
}

@Test func incompatibleChildStreamDoesNotDisableRootTaskStatus() throws {
    let f = try SessionFixture()
    try f.owner(); try f.snapshot(false, runtime: "active", status: "inProgress")
    let child = UUID().uuidString
    f.session.agentIDs.insert(child); f.session.streamIssues.insert(child)
    #expect(f.snapshot.features[.tasks]?.state == .available)
    #expect(f.snapshot.counts?.processing == 1)
    #expect(f.snapshot.features[.agents]?.state == .partial)
}

@Test func idleHistoryWithoutSidecarsRecoversDoneWithoutIPCOrUserActivity() throws {
    let f = try SessionFixture()
    try f.writeUnread(true)
    let path = f.home.appendingPathComponent("thread_history_1.sqlite").path
    var writer: OpaquePointer?
    #expect(sqlite3_open(path, &writer) == SQLITE_OK)
    #expect(sqlite3_exec(writer, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK)
    var persist: Int32 = 0
    #expect(sqlite3_file_control(writer, "main", SQLITE_FCNTL_PERSIST_WAL, &persist) == SQLITE_OK)
    #expect(sqlite3_close(writer) == SQLITE_OK)
    #expect(!FileManager.default.fileExists(atPath: path + "-wal"))
    for _ in 0..<3 {
        try f.session.refreshRecovery()
        #expect(f.snapshot.counts?.done == 1)
        #expect(f.snapshot.features[.history]?.state == .available)
        #expect(f.session.sourceFailures.failures[.completions] == nil)
        #expect(f.snapshot.audioEvents.isEmpty)
    }
    #expect(f.transport.sent.isEmpty) // Recovery did not need a live conversation or new prompt.
}
