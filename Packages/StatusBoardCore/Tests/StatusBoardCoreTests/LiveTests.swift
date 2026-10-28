import Foundation
import Testing
import SQLite3
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private func observed(runtime: String = "idle", status: String = "completed", unread: String = "false", flags: String = "[]", requests: String = "[]") throws -> DesktopObservation {
    let json = """
    {"type":"snapshot","revision":1,"conversationState":{"id":"T","hostId":"local",
    "hasUnreadTurn":\(unread),"threadRuntimeStatus":{"type":"\(runtime)","activeFlags":\(flags)},
    "requests":\(requests),"turns":[{"turnId":"R","status":"\(status)"}]}}
    """
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: JSONDecoder().decode(WireValue.self, from: Data(json.utf8)), owner: "owner")
    return try #require(stream.observation)
}

@Test func liveCountsPreferBlockingFlagsAndRequireUnreadEvidence() throws {
    let processing = try observed(runtime: "active", status: "inProgress")
    let waiting = try observed(runtime: "active", status: "inProgress", flags: #"["waitingOnApproval"]"#)
    let unread = try observed(unread: "true")
    let read = try observed()
    let unknown = try observed(unread: "null")
    let (counts, coverage) = LiveClassification.counts([processing, waiting, unread, read, unknown])
    #expect(counts == TaskCounts(processing: 1, waiting: 1, done: 1))
    #expect(coverage == 4)
}

@Test func unknownRequestDoesNotBecomeProcessingOrWaiting() throws {
    let unknown = try observed(runtime: "active", status: "inProgress", requests: #"[{"id":1,"method":"future/request","params":{"turnId":"R"}}]"#)
    #expect(LiveClassification.state(unknown) == .unknown)
    #expect(LiveClassification.counts([unknown]).1 == 0)
}

@Test func missedReadNotificationReconcilesSameRevisionWithoutClearingRealUnread() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    func snapshot(_ unread: Bool) throws -> WireValue {
        try JSONDecoder().decode(WireValue.self, from: Data("""
        {"type":"snapshot","revision":7,"conversationState":{"id":"T","hostId":"local",
        "hasUnreadTurn":\(unread),"threadRuntimeStatus":{"type":"idle","activeFlags":[]},
        "requests":[],"turns":[{"turnId":"R","status":"completed"}]}}
        """.utf8))
    }
    _ = try stream.accept(change: snapshot(true), owner: "owner")
    var refresh = UnreadReconciliation()
    #expect(refresh.due(observations: ["T": try #require(stream.observation)], pending: [], now: 0).isEmpty)
    #expect(refresh.due(observations: ["T": try #require(stream.observation)], pending: [], now: 1) == ["T"])
    // A still-unread owner response must retain Done and allow another check.
    #expect(try stream.accept(change: snapshot(true), owner: "owner").isEmpty)
    #expect(LiveClassification.counts([try #require(stream.observation)]).0.done == 1)
    #expect(refresh.due(observations: ["T": try #require(stream.observation)], pending: [], now: 5).isEmpty)
    #expect(refresh.due(observations: ["T": try #require(stream.observation)], pending: [], now: 6) == ["T"])
    // No file event or runtime patch; a same-revision owner snapshot corrects it.
    #expect(try stream.accept(change: snapshot(false), owner: "owner").isEmpty)
    #expect(LiveClassification.counts([try #require(stream.observation)]).0.done == 0)
    #expect(refresh.due(observations: ["T": try #require(stream.observation)], pending: [], now: 12).isEmpty)
}

@Test func unreadReconciliationDoesNotExtendInflightTimeoutsOrRetainRemovedRuns() throws {
    let unread = try observed(unread: "true")
    var refresh = UnreadReconciliation()
    #expect(refresh.due(observations: ["T": unread], pending: [], now: 0).isEmpty)
    #expect(refresh.due(observations: ["T": unread], pending: ["T"], now: 2).isEmpty)
    #expect(refresh.due(observations: ["T": unread], pending: [], now: 3) == ["T"])
    // New runs, read results, unavailable sources, and removed threads don't poll.
    #expect(refresh.due(observations: ["T": try observed(runtime: "active", status: "inProgress", unread: "true")], pending: [], now: 10).isEmpty)
    #expect(refresh.due(observations: ["T": try observed(unread: "null")], pending: [], now: 11).isEmpty)
    #expect(refresh.due(observations: [:], pending: [], now: 12).isEmpty)
    #expect(refresh.due(observations: ["T": unread], pending: [], now: 20).isEmpty)
    #expect(refresh.due(observations: ["T": unread], pending: [], now: 21) == ["T"])
}

@Test func completedErrorAndStoppedRemainDistinct() throws {
    #expect(LiveClassification.state(try observed(status: "failed")) == .waitingError)
    #expect(LiveClassification.state(try observed(status: "interrupted")) == .stopped)
    #expect(LiveClassification.state(try observed(runtime: "systemError")) == .waitingError)
}

@Test func inventoryExcludesOtherAccountsArchivedAndChildrenWithoutReadingBodies() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let ids = (0..<6).map { _ in UUID().uuidString }
    let sql = """
    CREATE TABLE threads (id TEXT,creator_account_id TEXT,source TEXT,archived INTEGER,recency_at_ms INTEGER,updated_at INTEGER);
    CREATE TABLE thread_spawn_edges (parent_thread_id TEXT,child_thread_id TEXT);
    INSERT INTO threads VALUES ('\(ids[0])','A','vscode',0,0,0),('\(ids[1])','B','vscode',0,0,0),
    ('\(ids[2])','A','vscode',1,0,0),('\(ids[3])','A','vscode',0,0,0),
    ('\(ids[4])',NULL,'vscode',0,0,0),('\(ids[5])','A','subagent',0,0,0);
    INSERT INTO thread_spawn_edges VALUES ('\(ids[0])','\(ids[3])');
    """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    let result = try LocalInventory(path: path).read(account: "A")
    #expect(result.ids == [ids[0]])
    #expect(result.total == 1)
    #expect(result.unassigned == 1)
    #expect(result.titles.isEmpty) // Older schemas still provide counts.
    #expect(sqlite3_exec(db, "ALTER TABLE threads ADD COLUMN title TEXT; UPDATE threads SET title='PRIVATE_FIRST_USER_PROMPT';", nil, nil, nil) == SQLITE_OK)
    // A legacy title is not a sidebar name and must never be shown.
    #expect(try LocalInventory(path: path).read(account: "A").titles.isEmpty)
    #expect(sqlite3_exec(db, "ALTER TABLE threads ADD COLUMN name TEXT; UPDATE threads SET name='Private other name';", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, "UPDATE threads SET name='Fix panel labels' WHERE id='\(ids[0])';", nil, nil, nil) == SQLITE_OK)
    let titled = try LocalInventory(path: path).read(account: "A")
    #expect(titled.ids == result.ids)
    #expect(titled.titles == [ids[0]: "Fix panel labels"])
    #expect(sqlite3_exec(db, "UPDATE threads SET name='Renamed chat' WHERE id='\(ids[0])';", nil, nil, nil) == SQLITE_OK)
    #expect(try LocalInventory(path: path).read(account: "A").titles == [ids[0]: "Renamed chat"])
    #expect(sqlite3_exec(db, "UPDATE threads SET name=NULL WHERE id='\(ids[0])';", nil, nil, nil) == SQLITE_OK)
    #expect(try LocalInventory(path: path).read(account: "A").titles.isEmpty)
}
