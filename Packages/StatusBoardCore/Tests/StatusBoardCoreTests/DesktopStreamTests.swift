import Foundation
import Testing
@testable import StatusBoardCore

private func wire(_ text: String) throws -> WireValue { try JSONDecoder().decode(WireValue.self, from: Data(text.utf8)) }
private func snapshot(_ revision: Int = 1, status: String = "inProgress", unread: Bool = false) throws -> WireValue {
    try wire("""
    {"type":"snapshot","revision":\(revision),"conversationState":{
      "id":"T","hostId":"local","hasUnreadTurn":\(unread),
      "threadRuntimeStatus":{"type":"active","activeFlags":[]},"requests":[],
      "turns":[{"turnId":"R","status":"\(status)","items":[{"text":"PRIVATE_SENTINEL"}]}],
      "title":"PRIVATE_SENTINEL","cwd":"PRIVATE_SENTINEL"}}
    """)
}
private func patches(_ next: Int, _ body: String) throws -> WireValue {
    try wire("{\"type\":\"patches\",\"baseRevision\":\(next - 1),\"revision\":\(next),\"patches\":[\(body)]}")
}

@Test func splitAndCoalescedFramesDecodeWithoutAlignmentAssumptions() throws {
    let body = Data("{\"type\":\"response\"}".utf8)
    let bytes = Data([UInt8(body.count), 0, 0, 0]) + body
    var decoder = DesktopMetadataDecoder()
    #expect(try decoder.append(bytes.prefix(3)).isEmpty)
    #expect(try decoder.append(bytes.dropFirst(3) + bytes) == [try wire(String(decoding: body, as: UTF8.self)), try wire(String(decoding: body, as: UTF8.self))])
    #expect(throws: DesktopStreamError.self) { try decoder.append(Data([255,255,255,255])) }
}

@Test func desktopProjectionDropsContentAndTracksTextOnlyRevisions() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    #expect(try stream.accept(change: snapshot(), owner: "O").isEmpty)
    let stored = String(decoding: try JSONEncoder().encode(stream.metadata), as: UTF8.self)
    #expect(!stored.contains("PRIVATE_SENTINEL"))
    let textDelta = try patches(2, #"{"op":"replace","path":["turns",0,"items",0,"text"],"value":"MORE_PRIVATE"}"#)
    #expect(try stream.accept(change: textDelta, owner: "O").isEmpty)
    #expect(stream.revision == 2)
    #expect(!String(decoding: try JSONEncoder().encode(stream.metadata), as: UTF8.self).contains("MORE_PRIVATE"))
}

@Test func desktopFrameCapRejectsOversizeBeforeBufferingBody() throws {
    var decoder = DesktopMetadataDecoder()
    var length = UInt32(DesktopMetadataDecoder.wireLimit + 1).littleEndian
    let header = withUnsafeBytes(of: &length) { Data($0) }
    #expect(try decoder.append(header.prefix(3)).isEmpty)
    #expect(throws: DesktopStreamError.self) { try decoder.append(header.suffix(1)) }
    #expect(throws: DesktopStreamError.self) { try decoder.append(Data([0, 0, 0, 0])) }
    #expect(try decoder.append(Data([2, 0, 0, 0, 123, 125])) == [.object([:])])
}

@Test func completeAndUnreadAreSeparateAndReadRefreshCanShareRevision() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let completion = try patches(2, #"{"op":"replace","path":["turns",0,"status"],"value":"completed"}"#)
    let events = try stream.accept(change: completion, owner: "O")
    #expect(events.map(\.kind) == [.completed])
    #expect(stream.observation?.unread == false)
    let unread = try patches(3, #"{"op":"replace","path":["hasUnreadTurn"],"value":true}"#)
    #expect(try stream.accept(change: unread, owner: "O").isEmpty)
    #expect(stream.observation?.unread == true)
    #expect(try stream.accept(change: snapshot(3, status: "completed", unread: false), owner: "O").isEmpty)
    #expect(stream.observation?.unread == false)
    #expect(try stream.accept(change: completion, owner: "O").isEmpty)
}

@Test func revisionGapClearsDataAndRecoveryIsSilent() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    #expect(throws: DesktopStreamError.self) { try stream.accept(change: patches(3, ""), owner: "O") }
    #expect(stream.needsSnapshot)
    #expect(stream.observation == nil)
    #expect(try stream.accept(change: snapshot(5, status: "completed", unread: true), owner: "O").isEmpty)
    stream.invalidate()
    #expect(stream.observation == nil)
}

@Test func ownerChangeRequiresNewBaseline() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    #expect(throws: DesktopStreamError.self) { try stream.accept(change: patches(2, ""), owner: "other") }
    #expect(stream.needsSnapshot)
    #expect(try stream.accept(change: snapshot(1, status: "completed"), owner: "other").isEmpty)
}

@Test func patchBatchCommitsAtomicallyAndInvalidIndexFailsClosed() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let invalid = try patches(2, #"{"op":"replace","path":["hasUnreadTurn"],"value":true},{"op":"remove","path":["turns",99]}"#)
    #expect(throws: DesktopStreamError.self) { try stream.accept(change: invalid, owner: "O") }
    #expect(stream.metadata == .null)
}

@Test func malformedSelectedPathCannotSilentlyAdvanceRevision() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let invalid = try patches(2, #"{"op":"replace","path":["turns","0","status"],"value":"completed"}"#)
    #expect(throws: DesktopStreamError.self) { try stream.accept(change: invalid, owner: "O") }
    #expect(stream.needsSnapshot)
}

@Test func shortWaitWithStableRequestIDIsObservedOnce() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let start = try patches(2, #"{"op":"add","path":["requests",0],"value":{"id":41,"method":"item/tool/requestUserInput","params":{"turnId":"R","questions":["PRIVATE"]}}}"#)
    let event = try stream.accept(change: start, owner: "O")
    #expect(event.map(\.kind) == [.waiting])
    #expect(event.first?.occurrence == "T:R:item/tool/requestUserInput:41")
    #expect(try stream.accept(change: start, owner: "O").isEmpty)
    #expect(try stream.accept(change: patches(3, #"{"op":"remove","path":["requests",0]}"#), owner: "O").isEmpty)
    #expect(stream.observation?.pendingRequestIDs.isEmpty == true)
}

@Test func unknownRequestsAreNotInventedWaitEpisodes() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let unknown = try patches(2, #"{"op":"add","path":["requests",0],"value":{"id":"x","method":"item/tool/call","params":{"turnId":"R"}}}"#)
    #expect(try stream.accept(change: unknown, owner: "O").isEmpty)
    #expect(stream.observation?.hasUnclassifiedRequests == true)
}

@Test func canonicalHistoryUsesOrderedNewestIslandAndRequiresTailCoverage() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    let canonical = try wire(#"{"type":"snapshot","revision":1,"conversationState":{"id":"T","hostId":"local","turns":[],"turnHistory":{"kind":"canonical","history":{"islands":[{"newerBoundary":{"status":"exhausted"},"entries":[{"value":"z"},{"value":"a"}]}],"entitiesByKey":{"a":{"turnId":"new","status":"inProgress"},"z":{"turnId":"old","status":"completed"}}}}}}"#)
    _ = try stream.accept(change: canonical, owner: "O")
    #expect(stream.observation?.runID == "new")
    _ = try stream.accept(change: patches(2, #"{"op":"replace","path":["turnHistory","history","islands",0,"newerBoundary","status"],"value":"unknown"}"#), owner: "O")
    #expect(stream.observation?.runID == nil)
    #expect(stream.observation?.hasLatestTurnCoverage == false)
}

@Test func heartbeatAndBootstrapDoNotGenerateCompletionSounds() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    #expect(try stream.accept(change: snapshot(1, status: "completed", unread: true), owner: "O").isEmpty)
    _ = try stream.accept(change: snapshot(2), owner: "O")
    let heartbeat = try patches(3, #"{"op":"add","path":["turns",0,"automationKind"],"value":"heartbeat"},{"op":"replace","path":["turns",0,"status"],"value":"completed"}"#)
    #expect(try stream.accept(change: heartbeat, owner: "O").isEmpty)
}

@Test func waitFlagsAndRequestsShareOneEpisodeAndNextWaitSoundsAgain() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let flag = #"{"op":"replace","path":["threadRuntimeStatus","activeFlags"],"value":["waitingOnApproval"]}"#
    #expect(try stream.accept(change: patches(2, flag), owner: "O").map(\.kind) == [.waiting])
    let request = #"{"op":"add","path":["requests",0],"value":{"id":41,"method":"item/commandExecution/requestApproval","params":{"turnId":"R"}}}"#
    #expect(try stream.accept(change: patches(3, request), owner: "O").isEmpty)
    let clear = #"{"op":"replace","path":["requests"],"value":[]},{"op":"replace","path":["threadRuntimeStatus","activeFlags"],"value":[]}"#
    #expect(try stream.accept(change: patches(4, clear), owner: "O").isEmpty)
    #expect(try stream.accept(change: patches(5, flag), owner: "O").map(\.kind) == [.waiting])
}

@Test func stoppedFailureAfterRetryAndIntentionalStopHaveDifferentAlerts() throws {
    var stream = DesktopStream(conversationID: "T", hostID: "local")
    _ = try stream.accept(change: snapshot(), owner: "O")
    let failed = #"{"op":"replace","path":["turns",0,"status"],"value":"failed"}"#
    #expect(try stream.accept(change: patches(2, failed), owner: "O").isEmpty) // Still active/retrying.
    let stopped = #"{"op":"replace","path":["threadRuntimeStatus","type"],"value":"idle"}"#
    #expect(try stream.accept(change: patches(3, stopped), owner: "O").map(\.kind) == [.failed])
    #expect(try stream.accept(change: patches(4, stopped), owner: "O").isEmpty)
    _ = try stream.accept(change: snapshot(5), owner: "O")
    let interrupted = #"{"op":"replace","path":["turns",0,"status"],"value":"interrupted"},{"op":"replace","path":["threadRuntimeStatus","type"],"value":"idle"}"#
    #expect(try stream.accept(change: patches(6, interrupted), owner: "O").isEmpty)
    _ = try stream.accept(change: snapshot(7, status: "failed"), owner: "O") // Active retry.
    let recovered = #"{"op":"replace","path":["turns",0,"status"],"value":"completed"}"#
    #expect(try stream.accept(change: patches(8, recovered), owner: "O").map(\.kind) == [.completed])
}
