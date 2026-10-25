import Foundation
import Testing
import SQLite3
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private func reviewSnapshot(runtime: String, flags: [String] = [], history: [String: Any]) throws -> WireValue {
    let object: [String: Any] = ["type": "snapshot", "revision": 1, "conversationState": [
        "id": "T", "hostId": "local", "hasUnreadTurn": true,
        "threadRuntimeStatus": ["type": runtime, "activeFlags": flags], "requests": [],
        "turnHistory": ["kind": "canonical", "history": history]]]
    return try JSONDecoder().decode(WireValue.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func incompleteHistoryPreservesRuntimeWithoutRestoringAnOldCompletion() throws {
    for (runtime, flags, expected) in [
        ("active", [String](), TaskState.processing),
        ("active", ["waitingOnApproval"], .waitingUser),
        ("systemError", [], .waitingError), ("idle", [], .unknown)
    ] {
        var stream = DesktopStream(conversationID: "T", hostID: "local")
        #expect(try stream.accept(change: reviewSnapshot(runtime: runtime, flags: flags, history: [:]), owner: "O").isEmpty)
        let observation = try #require(stream.observation)
        #expect(observation.runID == nil)
        #expect(!observation.hasLatestTurnCoverage)
        #expect(LiveClassification.state(observation) == expected)
        #expect(StoredCompletions.unloaded(["T"], eligible: ["T"], liveThreads: ["T"]).isEmpty)
        #expect(LiveClassification.counts([observation]).0.done == 0)
        stream.invalidate()
        #expect(stream.observation == nil)
        #expect(StoredCompletions.unloaded(["T"], eligible: ["T"], liveThreads: ["T"]).isEmpty)
    }
}

@Test func missingNewestEntityCannotExposeAnOlderCompletedTurn() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    let history: [String: Any] = [
        "islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "old"], ["value": "missing"]]]],
        "entitiesByKey": ["old": ["turnId": "old", "status": "completed"]]]
    _ = try stream.accept(change: reviewSnapshot(runtime: "idle", history: history), owner: "O")
    #expect(LiveClassification.state(try #require(stream.observation)) == .unknown)
    #expect(stream.observation?.runID == nil)
}

@Test func inventoryBeyond512RetainsOldUnreadCompletion() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let ids = (0..<513).map { _ in UUID().uuidString }
    let rows = ids.enumerated().map { "('\($0.element)','A','vscode',0,\($0.offset),0)" }.joined(separator: ",")
    let sql = """
    CREATE TABLE threads (id TEXT,creator_account_id TEXT,source TEXT,archived INTEGER,recency_at_ms INTEGER,updated_at INTEGER);
    CREATE TABLE thread_spawn_edges (parent_thread_id TEXT,child_thread_id TEXT);
    CREATE TABLE thread_turns (thread_id TEXT,rollout_ordinal INTEGER,status TEXT,completed_at INTEGER);
    INSERT INTO threads VALUES \(rows);
    INSERT INTO thread_turns VALUES ('\(ids[0])',1,'completed',1);
    """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    let inventory = try LocalInventory(path: path).read(account: "A")
    #expect(inventory.total == 513)
    #expect(inventory.ids.count == 513)
    #expect(inventory.ids.last == ids[0])
    let completed = try StoredCompletions(path: path).read(candidates: Set(inventory.ids))
    #expect(completed == [ids[0]])
}

@Test func healthySessionResetsReconnectBackoffEvenWhenItEndsByThrowing() {
    var retry = ReconnectBackoff()
    #expect((0..<6).map { _ in retry.nextDelay(afterHealthySession: false) } == [1, 2, 4, 8, 15, 15])
    #expect(retry.nextDelay(afterHealthySession: true) == 1)
    #expect(retry.nextDelay(afterHealthySession: false) == 2)
    #expect(retry.nextDelay(afterHealthySession: true) == 1)
}

@Test func heartbeatUnreadCountsAgreeAcrossRecoveryAndLiveWithoutBaselineAlerts() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    let history: [String: Any] = [
        "islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "R"]]]],
        "entitiesByKey": ["R": ["turnId": "R", "status": "completed", "automationKind": "heartbeat"]]]
    let change = try reviewSnapshot(runtime: "idle", history: history)
    let restored = StoredCompletions.unloaded(["T"], eligible: ["T"], liveThreads: [])
    #expect(try stream.accept(change: change, owner: "O").isEmpty)
    #expect(LiveClassification.counts([try #require(stream.observation)]).0.done == restored.count)
    stream.invalidate()
    #expect(try stream.accept(change: change, owner: "new-owner").isEmpty)
    #expect(LiveClassification.counts([try #require(stream.observation)]).0.done == 1)
}

@Test func discoveryCyclesDoNotStarveTheTailOrDuplicatePendingWork() {
    let ids = Set((0..<600).map { String(format: "%04d", $0) })
    var queue = DiscoveryQueue()
    queue.enqueue(ids)
    #expect(queue.next(eligible: ids, pending: []) == "0000")
    queue.enqueue(ids) // A timer fires before the first cycle has finished.
    for i in 1..<600 {
        #expect(queue.next(eligible: ids, pending: []) == String(format: "%04d", i))
    }
    #expect(queue.next(eligible: ids, pending: []) == "0000")
    #expect(queue.next(eligible: ids, pending: []) == nil)
    queue.enqueue(["archived", "pending", "ready"])
    #expect(queue.next(eligible: ["pending", "ready"], pending: ["pending"]) == "ready")
    #expect(queue.next(eligible: ids, pending: []) == nil)
}

@Test func threadCleanupKeepsTimeoutDistinctFromConfirmedUnload() throws {
    var threads = ThreadTracking()
    #expect(threads.assign("T", owner: "O") == true)
    threads.snapshotDeadlines["T"] = 5
    #expect(threads.assign("T", owner: "O") == false)
    #expect(threads.snapshotDeadlines["T"] == 5)
    #expect(threads.assign("T", owner: "new-owner") == true)
    #expect(threads.snapshotDeadlines["T"] == nil)
    #expect(threads.observations.isEmpty)
    #expect(threads.recoveryBlocked == ["T"])
    _ = try threads.streams["T"]?.accept(change: reviewSnapshot(runtime: "active", history: [:]), owner: "new-owner")
    #expect(threads.observations["T"]?.runtime == "active")
    threads.snapshotDeadlines["T"] = 10
    threads.remove("T", allowRecovery: false)
    #expect(threads.owners.isEmpty && threads.streams.isEmpty && threads.snapshotDeadlines.isEmpty)
    #expect(StoredCompletions.unloaded(["T"], eligible: ["T"], liveThreads: threads.recoveryBlocked).isEmpty)
    threads.remove("T", allowRecovery: true)
    #expect(StoredCompletions.unloaded(["T"], eligible: ["T"], liveThreads: threads.recoveryBlocked) == ["T"])
}

@Test func failedDiscoveryDoesNotImplyAnUnloadedThread() throws {
    func result(_ json: String) throws -> OwnerDiscoveryResult {
        OwnerDiscoveryResult(try JSONDecoder().decode(WireValue.self, from: Data(json.utf8)))
    }
    #expect(try result(#"{"resultType":"success","handledByClientId":"O"}"#) == .owner("O"))
    #expect(try result(#"{"resultType":"error","error":"no-client-found"}"#) == .unloaded)
    for error in ["request-timeout", "client-disconnected", "server-closed"] {
        #expect(try result("{\"resultType\":\"error\",\"error\":\"\(error)\"}") == .unavailable)
    }
    #expect(try result(#"{"resultType":"success"}"#) == .incompatible)
    #expect(try result(#"{"resultType":"success","handledByClientId":""}"#) == .incompatible)
}
