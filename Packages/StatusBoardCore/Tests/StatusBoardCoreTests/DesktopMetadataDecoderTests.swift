import Foundation
import Testing
@testable import StatusBoardCore

private func metadataFrame(_ data: Data) -> Data {
    var length = UInt32(data.count).littleEndian
    return withUnsafeBytes(of: &length) { Data($0) } + data
}
private func metadataEnvelope(_ change: String) -> String {
    """
    {"type":"broadcast","method":"thread-stream-state-changed","version":11,"sourceClientId":"O",
     "params":{"hostId":"local","conversationId":"T","change":\(change)}}
    """
}
private func metadataSnapshot(_ text: String = "ignored", items: String? = nil) -> String {
    let items = items ?? #"[{"id":"I","type":"agentMessage","text":"\#(text)"}]"#
    return """
    {"type":"snapshot","revision":1,"conversationState":{"id":"T","hostId":"local",
    "hasUnreadTurn":false,"threadRuntimeStatus":{"type":"active","activeFlags":[]},"requests":[],
    "turns":[{"turnId":"R","status":"inProgress","items":\(items)}]}}
    """
}
private func metadataDecode(_ json: String, chunkSize: Int = 65536) throws -> (WireValue, Int) {
    var decoder = DesktopMetadataDecoder()
    let bytes = metadataFrame(Data(json.utf8))
    var messages: [WireValue] = []
    for offset in stride(from: 0, to: bytes.count, by: chunkSize) {
        messages += try decoder.append(bytes.subdata(in: offset..<min(offset + chunkSize, bytes.count)))
    }
    return (try #require(messages.first), decoder.lastRetainedBytes)
}
private func jsonString(_ text: String) throws -> String {
    String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
}

@Test func streamingLargeSnapshotSkipsContentAndPreservesNextFrame() throws {
    let text = String(repeating: "x", count: 9 * 1024 * 1024)
    let body = metadataEnvelope(metadataSnapshot(text))
    let completion = metadataEnvelope(#"{"type":"patches","baseRevision":1,"revision":2,"patches":[{"op":"replace","path":["turns",0,"status"],"value":"completed"}]}"#)
    let bytes = metadataFrame(Data(body.utf8)) + metadataFrame(Data(completion.utf8))
    var decoder = DesktopMetadataDecoder()
    var messages: [WireValue] = []
    #expect(try decoder.append(bytes.prefix(2)).isEmpty)
    var maxRetained = 0
    for offset in stride(from: 2, to: bytes.count, by: 65536) {
        messages += try decoder.append(bytes.subdata(in: offset..<min(offset + 65536, bytes.count)))
        maxRetained = max(maxRetained, decoder.lastRetainedBytes)
    }
    #expect(messages.count == 2)
    #expect(maxRetained < 4096)
    guard messages.count == 2 else { return }
    #expect(try JSONEncoder().encode(messages[0]).count < 1024)
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    #expect(try stream.accept(change: messages[0]["params"]["change"], owner: "O").isEmpty)
    #expect(stream.observation?.runtime == "active")
    #expect(try stream.accept(change: messages[1]["params"]["change"], owner: "O").map(\.kind) == [.completed])
}

@Test func streamingLargePatchesWorkWithValueBeforeOrAfterPath() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: metadataDecode(metadataEnvelope(metadataSnapshot())).0["params"]["change"], owner: "O")
    let text = String(repeating: "z", count: 9 * 1024 * 1024)
    for revision in 2...3 {
        let fields = revision == 2
            ? #""op":"replace","path":["turns",0,"items",0,"text"],"value":"\#(text)""#
            : #""value":"\#(text)","path":["turns",0,"items",0,"text"],"op":"replace""#
        let json = metadataEnvelope(#"{"type":"patches","revision":\#(revision),"baseRevision":\#(revision - 1),"patches":[{\#(fields)}]}"#)
        let (message, retained) = try metadataDecode(json)
        #expect(retained < 4096)
        #expect(try stream.accept(change: message["params"]["change"], owner: "O").isEmpty)
        #expect(stream.revision == revision)
    }
    let (message, _) = try metadataDecode(metadataEnvelope(#"{"type":"patches","baseRevision":3,"revision":4,"patches":[{"value":"completed","op":"replace","path":["turns",0,"status"]}]}"#))
    #expect(try stream.accept(change: message["params"]["change"], owner: "O").map(\.kind) == [.completed])
}

@Test func streamingAnswersKeepExactIDsAndDiscardLongQuestionAndAnswer() throws {
    let key = #"["request_user_input_async","Q  🦖",0]"#
    let answer: [[String: Any]] = [["questionItemId": key, "question": String(repeating: "q", count: 100_000), "answer": String(repeating: "a", count: 100_000)]]
    let answerJSON = String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
    let reply = " \n<send_user_message_question_reply>\n" + answerJSON + "\n</send_user_message_question_reply>\n "
    let items = """
    [{"id":"Q  🦖","type":"agentMessage","questions":[{"title":"private"}]},
    {"type":"steeringUserMessage","status":"accepted","input":[{"type":"text","text":\(try jsonString(reply))}]}]
    """
    let raw = metadataEnvelope(metadataSnapshot(items: items))
    let (projected, retained) = try metadataDecode(raw, chunkSize: 7)
    #expect(retained < 4096)
    var direct = DesktopStream(conversationID: "T", hostID: "local")
    var filtered = DesktopStream(conversationID: "T", hostID: "local")
    let full = try JSONDecoder().decode(WireValue.self, from: Data(raw.utf8))
    _ = try direct.accept(change: full["params"]["change"], owner: "O")
    _ = try filtered.accept(change: projected["params"]["change"], owner: "O")
    #expect(direct.metadata == filtered.metadata)
    #expect(filtered.observation?.pendingRequestIDs.isEmpty == true)
}

@Test func streamingMalformedReplyCannotClearPendingQuestion() throws {
    let reply = #"<send_user_message_question_reply>[{"questionItemId":"Q","question":42,"answer":"no"}]</send_user_message_question_reply>"#
    let items = """
    [{"id":"Q","type":"agentMessage","questions":[{}]},
     {"type":"userMessage","content":[{"type":"text","text":\(try jsonString(reply))}]}]
    """
    let (message, _) = try metadataDecode(metadataEnvelope(metadataSnapshot(items: items)), chunkSize: 1)
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: message["params"]["change"], owner: "O")
    #expect(stream.observation?.pendingRequestIDs.count == 1)
}

@Test func streamingEscapedKeysUnicodeAndDiscoveryEnvelopeSurviveByteSplits() throws {
    let json = #"{"ty\u0070e":"response","requestId":"A\uD83E\uDD96","resultType":"success","handledByClientId":"O","result":{"clientId":"C"},"ignored":{"text":"braces } ] \" \\ are text"}}"#
    let (message, _) = try metadataDecode(json, chunkSize: 1)
    #expect(message["type"].string == "response")
    #expect(message["requestId"].string == "A🦖")
    #expect(message["handledByClientId"].string == "O")
    #expect(message["result"]["clientId"].string == "C")
    #expect(message["ignored"] == .null)
}

@Test func streamingRejectsMalformedStructureAndBoundsSelectedData() throws {
    for json in [#"{"type":"broadcast",}"#, #"{"type":"broadcast""#, #"{"ignored":"bad\q"}"#, #"{"params":[]} trailing"#] {
        #expect(throws: (any Error).self) { try metadataDecode(json, chunkSize: 1) }
    }
    #expect(throws: DesktopStreamError.self) {
        try metadataDecode(#"{"type":"\#(String(repeating: "x", count: 65537))"}"#)
    }
    var decoder = DesktopMetadataDecoder()
    #expect(throws: DesktopStreamError.self) { try decoder.append(Data([255,255,255,255])) }
    let good = try decoder.append(metadataFrame(Data(#"{"type":"response"}"#.utf8)))
    #expect(good.first?["type"].string == "response")
}

@Test func streamingCanonicalHistoryAndValueFirstReplacementMatchProjection() throws {
    let state = #"{"id":"T","hostId":"local","hasUnreadTurn":true,"requests":[{"id":"A","method":"item/tool/requestUserInput","params":{"turnId":"R","private":"DROP"}}],"threadRuntimeStatus":{"type":"active","activeFlags":["waitingOnUserInput"]},"turns":[],"turnHistory":{"kind":"canonical","history":{"generation":4,"isComplete":true,"entitiesByKey":{"arbitrary-key":{"turnId":"R","status":"inProgress","items":[{"id":"Q","type":"agentMessage","questions":[{"title":"DROP"}],"text":"DROP"}]}},"islands":[{"id":"island","newerBoundary":{"status":"exhausted"},"entries":[{"value":"arbitrary-key"}]}]}}}"#
    let snapshot = #"{"type":"snapshot","revision":1,"conversationState":\#(state)}"#
    let replacement = #"{"type":"patches","revision":2,"baseRevision":1,"patches":[{"value":\#(state),"op":"replace","path":[]}]}"#
    var direct = DesktopStream(conversationID: "T", hostID: "local")
    var filtered = DesktopStream(conversationID: "T", hostID: "local")
    for change in [snapshot, replacement] {
        let envelope = metadataEnvelope(change)
        let full = try JSONDecoder().decode(WireValue.self, from: Data(envelope.utf8))
        let (projected, _) = try metadataDecode(envelope, chunkSize: 3)
        let fullEvents = try direct.accept(change: full["params"]["change"], owner: "O")
        let events = try filtered.accept(change: projected["params"]["change"], owner: "O")
        #expect(events == fullEvents)
        #expect(filtered.metadata == direct.metadata)
        #expect(filtered.observation?.pendingRequestIDs == direct.observation?.pendingRequestIDs)
    }
}

@Test(arguments: ["arbitrary-key", "text", "questions", "entitiesByKey"])
func streamingMapReplacementIsIndependentOfPatchFieldOrder(key: String) throws {
    let state = #"{"id":"T","hostId":"local","hasUnreadTurn":true,"threadRuntimeStatus":{"type":"idle"},"turnHistory":{"kind":"canonical","history":{"entitiesByKey":{"\#(key)":{"turnId":"R","status":"inProgress"}},"islands":[{"newerBoundary":{"status":"exhausted"},"entries":[{"value":"\#(key)"}]}]}}}"#
    let snapshot = #"{"type":"snapshot","revision":1,"conversationState":\#(state)}"#
    let fields = [
        #""op":"replace""#,
        #""path":["turnHistory","history","entitiesByKey"]"#,
        #""value":{"\#(key)":{"turnId":"R","status":"completed","items":[{"type":"agentMessage","text":"PRIVATE CONTENT"}]}}"#
    ]
    for order in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
        var direct = DesktopStream(conversationID: "T", hostID: "local")
        var filtered = DesktopStream(conversationID: "T", hostID: "local")
        let replacement = #"{"type":"patches","revision":2,"baseRevision":1,"patches":[{\#(order.map { fields[$0] }.joined(separator: ","))}]}"#
        for change in [snapshot, replacement] {
            let json = metadataEnvelope(change)
            let full = try JSONDecoder().decode(WireValue.self, from: Data(json.utf8))
            let (projected, _) = try metadataDecode(json, chunkSize: 1)
            let expectedEvents = try direct.accept(change: full["params"]["change"], owner: "O")
            let actualEvents = try filtered.accept(change: projected["params"]["change"], owner: "O")
            #expect(actualEvents == expectedEvents)
            #expect(filtered.metadata == direct.metadata)
            #expect(!String(decoding: try JSONEncoder().encode(filtered.metadata), as: UTF8.self).contains("PRIVATE CONTENT"))
        }
        #expect(filtered.observation?.status == "completed")
        #expect(filtered.revision == 2 && !filtered.needsSnapshot)
    }
}

@Test func valueFirstItemReplacementDiscardsProseBeforeStreamProjection() throws {
    let privateText = "PRIVATE_PROSE" + String(repeating: "x", count: 100_000)
    let value = #"{"type":"agentMessage","id":"I","text":"\#(privateText)","prompt":"\#(privateText)","questions":[{"title":"\#(privateText)"}]}"#
    let change = #"{"type":"patches","revision":2,"baseRevision":1,"patches":[{"value":\#(value),"path":["turns",0,"items",0],"op":"replace"}]}"#
    let (message, retained) = try metadataDecode(metadataEnvelope(change), chunkSize: 7)
    #expect(retained < 4096)
    #expect(!String(decoding: try JSONEncoder().encode(message), as: UTF8.self).contains("PRIVATE_PROSE"))
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: metadataDecode(metadataEnvelope(metadataSnapshot())).0["params"]["change"], owner: "O")
    _ = try stream.accept(change: message["params"]["change"], owner: "O")
    #expect(stream.observation?.pendingRequestIDs.count == 1)
}

@Test func unorderedTurnMapStillEnforcesMetadataBudget() throws {
    let status = String(repeating: "x", count: 60_000)
    let entries = (0..<141).map { #""key-\#($0)":{"turnId":"R","status":"\#(status)"}"# }.joined(separator: ",")
    let change = #"{"type":"patches","revision":2,"baseRevision":1,"patches":[{"value":{\#(entries)},"path":["turnHistory","history","entitiesByKey"],"op":"replace"}]}"#
    #expect(throws: DesktopStreamError.oversize) { try metadataDecode(metadataEnvelope(change)) }
}
