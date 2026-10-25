import Foundation
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private func asyncWire(_ object: [String: Any]) throws -> WireValue {
    try JSONDecoder().decode(WireValue.self, from: JSONSerialization.data(withJSONObject: object))
}
private func asyncSnapshot(_ items: [[String: Any]], canonical: Bool = false) throws -> WireValue {
    let turn: [String: Any] = ["turnId": "R", "status": "inProgress", "items": items]
    var state: [String: Any] = ["id": "T", "hostId": "local", "hasUnreadTurn": false,
        "threadRuntimeStatus": ["type": "active", "activeFlags": []], "requests": [], "turns": [turn]]
    if canonical {
        state["turns"] = []
        state["turnHistory"] = ["kind": "canonical", "history": ["entitiesByKey": ["R": turn],
            "islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "R"]]]]]]
    }
    return try asyncWire(["type": "snapshot", "revision": 1, "conversationState": state])
}
private func asyncPatch(_ revision: Int, path: [Any], op: String = "add", value: Any) throws -> WireValue {
    try asyncWire(["type": "patches", "baseRevision": revision - 1, "revision": revision,
        "patches": [["op": op, "path": path, "value": value]]])
}
private func question(_ id: String = "Q", count: Int = 1) -> [String: Any] {
    ["id": id, "type": "agentMessage", "text": "PRIVATE_SENTINEL",
     "questions": (0..<count).map { _ in ["title": "PRIVATE_SENTINEL", "options": ["PRIVATE_SENTINEL"]] }]
}
private func answer(_ id: String = "Q", index: Int = 0, accepted: Bool = true) throws -> [String: Any] {
    let key = String(decoding: try JSONSerialization.data(withJSONObject: ["request_user_input_async", id, index], options: [.withoutEscapingSlashes]), as: UTF8.self)
    let payload = try JSONSerialization.data(withJSONObject: [["questionItemId": key, "question": "PRIVATE_SENTINEL", "answer": "PRIVATE_SENTINEL"]])
    return ["id": "reply", "type": "steeringUserMessage", "status": accepted ? "accepted" : "pending",
        "input": [["type": "text", "text": "<send_user_message_question_reply>\n\(String(decoding: payload, as: UTF8.self))\n</send_user_message_question_reply>"]]]
}

@Test func asyncQuestionWithoutRuntimeFlagCountsAndAlertsThenAnswerClears() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: asyncSnapshot([]), owner: "O")
    let added = try asyncPatch(2, path: ["turns", 0, "items", 0], value: question())
    #expect(try stream.accept(change: added, owner: "O").map(\.kind) == [.waiting])
    #expect(LiveClassification.state(try #require(stream.observation)) == .waitingUser)
    #expect(try stream.accept(change: added, owner: "O").isEmpty)
    #expect(try stream.accept(change: asyncPatch(3, path: ["turns", 0, "items", 1], value: answer()), owner: "O").isEmpty)
    #expect(LiveClassification.state(try #require(stream.observation)) == .processing)
    let stored = String(decoding: try JSONEncoder().encode(stream.metadata), as: UTF8.self)
    #expect(!stored.contains("PRIVATE_SENTINEL"))
}

@Test func canonicalAsyncBootstrapIsSilentAndOnlyAcceptedRepliesClear() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    #expect(try stream.accept(change: asyncSnapshot([question(), answer(accepted: false)], canonical: true), owner: "O").isEmpty)
    #expect(LiveClassification.state(try #require(stream.observation)) == .waitingUser)
    let base: [Any] = ["turnHistory", "history", "entitiesByKey", "R", "items"]
    #expect(try stream.accept(change: asyncPatch(2, path: base + [1, "status"], op: "replace", value: "accepted"), owner: "O").isEmpty)
    #expect(LiveClassification.state(try #require(stream.observation)) == .processing)
    #expect(try stream.accept(change: asyncPatch(3, path: base + [2], value: question("Q2")), owner: "O").map(\.kind) == [.waiting])
}

@Test func partialAsyncAnswersAndCompletedTurnsDoNotLeaveFalseWaiting() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: asyncSnapshot([question(count: 2), answer()]), owner: "O")
    #expect(stream.observation?.pendingRequestIDs.count == 1)
    #expect(try stream.accept(change: asyncPatch(2, path: ["turns", 0, "items", 2], value: answer("other")), owner: "O").isEmpty)
    #expect(stream.observation?.pendingRequestIDs.count == 1)
    _ = try stream.accept(change: asyncPatch(3, path: ["turns", 0, "status"], op: "replace", value: "completed"), owner: "O")
    #expect(stream.observation?.pendingRequestIDs.isEmpty == true)
}

@Test func questionTextChangesDoNotReplayAndMalformedRepliesStayPending() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: asyncSnapshot([question()]), owner: "O")
    #expect(try stream.accept(change: asyncPatch(2, path: ["turns", 0, "items", 0, "questions", 0, "title"], op: "replace", value: "PRIVATE_SENTINEL"), owner: "O").isEmpty)
    let unrelated: [String: Any] = ["id": "reply", "type": "userMessage", "content": [["type": "text", "text": "<send_user_message_question_reply>invalid PRIVATE_SENTINEL</send_user_message_question_reply>"]]]
    _ = try stream.accept(change: asyncPatch(3, path: ["turns", 0, "items", 1], value: unrelated), owner: "O")
    #expect(stream.observation?.pendingRequestIDs.count == 1)
    #expect(!String(decoding: try JSONEncoder().encode(stream.metadata), as: UTF8.self).contains("PRIVATE_SENTINEL"))
}
