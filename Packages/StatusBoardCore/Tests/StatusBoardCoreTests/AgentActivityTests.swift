import Foundation
import Testing
import SQLite3
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private let childID = "11111111-1111-4111-8111-111111111111"
private let nestedID = "22222222-2222-4222-8222-222222222222"
private func agentWire(_ value: [String: Any]) throws -> WireValue {
    try JSONDecoder().decode(WireValue.self, from: JSONSerialization.data(withJSONObject: value))
}
private func activity(_ kind: String, id: String = childID, path: String = "/root/reviewer") -> [String: Any] {
    ["id": UUID().uuidString, "type": "subAgentActivity", "kind": kind, "agentThreadId": id, "agentPath": path,
     "prompt": "PRIVATE_AGENT_PROMPT", "text": "PRIVATE_AGENT_OUTPUT"]
}
private func agentStream(id: String = "root", status: String = "inProgress", items: [[String: Any]] = []) throws -> DesktopStream {
    var stream = DesktopStream(conversationID: id, hostID: "local")
    let envelope: [String: Any] = ["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
        "params": ["hostId": "local", "conversationId": id, "change": ["type": "snapshot", "revision": 1,
            "conversationState": ["id": id, "hostId": "local", "requests": [], "hasUnreadTurn": false,
                "threadRuntimeStatus": ["type": status == "inProgress" ? "active" : "idle", "activeFlags": []],
                "turns": [["turnId": "run", "status": status, "items": items]]]]]]
    let data = try JSONSerialization.data(withJSONObject: envelope)
    var length = UInt32(data.count).littleEndian
    let frame = withUnsafeBytes(of: &length) { Data($0) } + data
    var decoder = DesktopMetadataDecoder()
    let message = try #require(decoder.append(frame).first)
    _ = try stream.accept(change: message["params"]["change"], owner: "owner")
    return stream
}

@Test func agentMetadataSurvivesIncrementalProjectionWithoutToolContents() throws {
    var stream = try agentStream(items: [activity("started")])
    #expect(stream.observation?.agents.first?.state == .running)
    let retained = String(decoding: try JSONEncoder().encode(stream.metadata), as: UTF8.self)
    #expect(!retained.contains("PRIVATE_AGENT"))
    let patch = try agentWire(["type": "patches", "baseRevision": 1, "revision": 2,
        "patches": [["op": "add", "path": ["turns", 0, "items", 1], "value": activity("completed")]]])
    _ = try stream.accept(change: patch, owner: "owner")
    #expect(stream.observation?.agents.count == 1)
    #expect(stream.observation?.agents.first?.state == .done)
}

@Test func messagesDoNotRestartCompletedAgentsAndNamesRemainBounded() throws {
    let stream = try agentStream(items: [activity("started"), activity("completed"), activity("interacted"),
        activity("started", id: nestedID, path: "/root"), activity("started", id: "invalid"),
        activity("started", id: nestedID, path: "/root/" + String(repeating: "x", count: 1024))])
    #expect(stream.observation?.agents.count == 1)
    #expect(stream.observation?.agents.first?.state == .done)
}

@Test func processingRowsTrackNestedAgentsAndRemoveOnlyFinishedRoot() throws {
    var observations = ["root": try #require(agentStream(items: [activity("started")]).observation),
        childID: try #require(agentStream(id: childID, items: [activity("started", id: nestedID, path: "/root/reviewer/tester")]).observation),
        nestedID: try #require(agentStream(id: nestedID, status: "completed").observation),
        "other": try #require(agentStream(id: "other").observation)]
    let rows = ProcessingAgents.rows(roots: ["root", "other"], observations: observations)
    #expect(rows.map(\.label) == ["root.....", "root.....", "reviewer.....", "tester done"])
    #expect(Set(rows.map(\.id)).count == rows.count)
    observations["root"]?.status = "completed" // Clear even before the runtime idle patch.
    #expect(ProcessingAgents.rows(roots: ["root", "other"], observations: observations).map(\.threadID) == ["other"])
    observations["other"]?.status = "completed"
    #expect(ProcessingAgents.rows(roots: ["root", "other"], observations: observations).isEmpty)
}

@Test func newTurnAndCoverageLossCannotLeakPreviousAgents() throws {
    var stream = try agentStream(items: [activity("started"), activity("completed")])
    let next = try agentWire(["type": "patches", "baseRevision": 1, "revision": 2,
        "patches": [["op": "add", "path": ["turns", 1], "value": ["turnId": "new-run", "status": "inProgress", "items": []]]]])
    _ = try stream.accept(change: next, owner: "owner")
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": try #require(stream.observation)]).map(\.label) == ["root....."])
    stream.invalidate()
    #expect(ProcessingAgents.rows(roots: ["root"], observations: [:]).isEmpty)
}

@Test func waitingAndStoppedAgentsAreNotPresentedAsRunningOrDone() throws {
    let parent = try #require(agentStream(items: [activity("started")]).observation)
    var child = try #require(agentStream(id: childID).observation)
    child.activeFlags = ["waitingOnApproval"]
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": parent, childID: child]).last?.state == .waiting)
    child.activeFlags = []; child.status = "interrupted"; child.runtime = "idle"
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": parent, childID: child]).last?.state == .stopped)
    var waitingParent = parent; waitingParent.activeFlags = ["waitingOnUserInput"]
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": waitingParent]).isEmpty)
}

@Test func storedAgentTurnsRequireExactLiveRootRunAndNeverRestoreOldRuns() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    var db: OpaquePointer?
    #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    func sql(_ text: String) throws {
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw DesktopFailure.unavailable }
    }
    try sql("""
        CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,root_turn_id TEXT,status TEXT,rollout_ordinal INTEGER);
        CREATE TABLE thread_items(thread_id TEXT,turn_id TEXT,item_type TEXT,item_json TEXT,rollout_ordinal INTEGER);
        INSERT INTO thread_turns VALUES ('\(childID)','child-run','run','inProgress',1);
        INSERT INTO thread_turns VALUES ('\(nestedID)','other-run','unrelated-root','completed',1);
        """)
    let reader = StoredAgentActivity(path: file.path)
    var root = try #require(agentStream(items: [activity("interacted")]).observation)
    var stored = try reader.read(roots: ["root": root])
    #expect(stored["run"]?.count == 1)
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": root], stored: stored).last?.label == "reviewer.....")
    try sql("UPDATE thread_turns SET status='completed' WHERE thread_id='\(childID)'")
    stored = try reader.read(roots: ["root": root])
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": root], stored: stored).last?.label == "reviewer done")
    root.runID = "next-root-run"
    #expect(try reader.read(roots: ["root": root]).isEmpty)
    #expect(ProcessingAgents.rows(roots: ["root"], observations: ["root": root], stored: stored).last?.state == .unknown)
    root.runID = "run"
    try sql("INSERT INTO thread_turns VALUES ('\(childID)','new-child-run','different-root','inProgress',2)")
    #expect(try reader.read(roots: ["root": root]).isEmpty)
    root.status = "completed"
    #expect(try reader.read(roots: ["root": root]).isEmpty)
}
