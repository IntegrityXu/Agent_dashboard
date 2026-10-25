import Foundation
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private final class SideTransport: DesktopTransport {
    var hasPendingBytes = false, hasPartialFrame = false
    var sent: [[String: Any]] = []
    func send(_ message: [String: Any]) throws { sent.append(message) }
    func receive(timeout: Int32) throws -> [WireValue] { [] }
}
private struct SideRPC: DesktopRPC {
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] { throw DesktopFailure.unavailable }
}
private final class SideClock { var now = 100.0 }
private final class SidePublications: @unchecked Sendable {
    let lock = NSLock()
    var values: [LiveSnapshot] = []
    func append(_ value: LiveSnapshot) { lock.withLock { values.append(value) } }
    var alerts: [LiveAlert] { lock.withLock { values.flatMap(\.audioEvents) } }
}
private final class SideFixture {
    let root = UUID().uuidString, side = UUID().uuidString
    let transport = SideTransport(), clock = SideClock(), publications = SidePublications()
    let session: DesktopSession
    init() throws {
        let transport = transport, clock = clock, publications = publications
        session = try DesktopSession(home: URL(fileURLWithPath: "/nonexistent/status-board-side-fixture"), rpc: SideRPC(),
            identity: .init(id: "fixture", namespace: "fixture", readScope: .init(identityKey: "fixture")),
            cancelled: { false }, refresh: { false }, publish: { publications.append($0) },
            transport: transport, uptime: { clock.now }, transportFactory: { transport })
        session.client = "observer"
        try inventory([root])
        try owner(root)
        try snapshot(root, runtime: "active", status: "inProgress", side: false)
    }
    func inventory(_ ids: [String]) throws {
        try session.applyInventory(.init(ids: ids, activity: [:], total: ids.count, unassigned: 0))
    }
    /// Exercise the production metadata decoder, not just unfiltered test JSON.
    func handle(_ object: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: object)
        let n = body.count
        let frame = Data([UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255), UInt8((n >> 24) & 255)]) + body
        var decoder = DesktopMetadataDecoder()
        for message in try decoder.append(frame) { try session.handle(message) }
    }
    func hint(_ id: String? = nil, viewer: String = "window", following: Bool = true, method: String = "thread-stream-following-changed", host: String = "local") throws {
        try handle(["type": "broadcast", "method": method, "version": 1, "sourceClientId": viewer,
            "params": ["hostId": host, "conversationId": id ?? side, "following": following]])
    }
    func owner(_ id: String) throws {
        try session.request(id)
        let key = try #require(transport.sent.last?["requestId"] as? String)
        try handle(["type": "response", "requestId": key, "resultType": "success", "handledByClientId": "owner"])
    }
    func snapshot(_ id: String? = nil, runtime: String = "active", status: String = "inProgress", side: Bool = true,
                  parent: String? = nil, ephemeral: Bool = true, subagent: Bool = false, sender: String = "owner") throws {
        let id = id ?? self.side
        var state: [String: Any] = ["id": id, "hostId": "local", "sideConversation": side, "ephemeral": ephemeral,
            "forkedFromId": parent ?? root, "hasUnreadTurn": false, "requests": [],
            "threadRuntimeStatus": ["type": runtime, "activeFlags": []], "turns": [["turnId": "run", "status": status]]]
        if subagent { state["parentThreadId"] = root }
        try handle(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": sender,
            "params": ["hostId": "local", "conversationId": id, "change": ["type": "snapshot", "revision": 1, "conversationState": state]]])
    }
    func patch(_ revision: Int, _ patches: [[String: Any]]) throws {
        try handle(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": "owner",
            "params": ["hostId": "local", "conversationId": side,
                "change": ["type": "patches", "baseRevision": revision - 1, "revision": revision, "patches": patches]]])
    }
    func activate() throws { try hint(); try owner(side); try snapshot() }
}

@Test func sideChatReplayDiscoversIndependentTaskAndLiveAlerts() throws {
    let f = try SideFixture()
    try f.hint()
    #expect(f.session.snapshot().counts?.processing == 1)
    #expect(f.session.discovery.next(eligible: f.session.followedIDs, pending: []) == f.side)
    try f.owner(f.side); try f.snapshot()
    #expect(f.session.snapshot().counts?.processing == 2)
    #expect(f.session.snapshot().total == 2)
    #expect(!f.session.ids.contains(f.side)) // Never added to database recovery.
    #expect(f.publications.alerts.isEmpty)
    try f.patch(2, [["op": "replace", "path": ["threadRuntimeStatus", "activeFlags"], "value": ["waitingOnUserInput"]]])
    #expect(f.session.snapshot().counts?.waiting == 1)
    #expect(f.session.snapshot().counts?.processing == 1)
    #expect(f.publications.alerts.last?.transition.kind == .waiting)
    try f.patch(3, [
        ["op": "replace", "path": ["threadRuntimeStatus"], "value": ["type": "idle"]],
        ["op": "replace", "path": ["turns", 0, "status"], "value": "completed"],
        ["op": "replace", "path": ["hasUnreadTurn"], "value": true]])
    #expect(f.session.snapshot().counts?.done == 1)
    #expect(f.publications.alerts.last?.transition.kind == .completed)
    try f.patch(4, [["op": "replace", "path": ["hasUnreadTurn"], "value": false]])
    #expect(f.session.snapshot().counts?.done == 0)
    #expect(f.publications.alerts.count == 2)
}

@Test func sideChatRemainsActiveWhenMainChatIsIdle() throws {
    let f = try SideFixture(); try f.activate()
    try f.snapshot(f.root, runtime: "idle", status: "completed", side: false)
    #expect(f.session.snapshot().counts?.processing == 1)
}

@Test(arguments: ["foreign-parent", "subagent", "ordinary", "durable", "spoofed-owner"])
func sideChatRequiresVerifiedScopeAndType(reason: String) throws {
    let f = try SideFixture(); try f.hint(); try f.owner(f.side)
    try f.snapshot(side: reason != "ordinary", parent: reason == "foreign-parent" ? UUID().uuidString : f.root,
        ephemeral: reason != "durable", subagent: reason == "subagent", sender: reason == "spoofed-owner" ? "stranger" : "owner")
    #expect(f.session.sideParents.isEmpty)
    #expect(f.session.snapshot().counts?.processing == 1)
    #expect(f.publications.alerts.isEmpty)
}

@Test func sideChatClosesOnlyAfterLastWindowAndReleasesSubscription() throws {
    let f = try SideFixture(); try f.activate(); try f.hint(viewer: "second-window")
    try f.hint(following: false); f.clock.now += 3; try f.session.refreshSideChats()
    #expect(f.session.sideParents.count == 1)
    try f.hint(viewer: "second-window", following: false)
    f.clock.now += 1; try f.hint(viewer: "second-window") // Remount cancels close.
    f.clock.now += 3; try f.session.refreshSideChats()
    #expect(f.session.sideParents.count == 1)
    try f.snapshot(runtime: "idle", status: "completed")
    try f.handle(["type": "broadcast", "method": "client-status-changed", "version": 0,
        "params": ["clientId": "second-window", "status": "disconnected"]])
    f.clock.now += 3; try f.session.refreshSideChats()
    #expect(f.session.sideParents.isEmpty)
    #expect(f.session.threads.owners[f.side] == nil)
    #expect(f.session.snapshot().counts?.processing == 1)
    #expect((f.transport.sent.last?["params"] as? [String: Any])?["following"] as? Bool == false)
}

@Test func sideChatCannotChangeParentOrOutliveAccountScope() throws {
    let f = try SideFixture(); try f.activate()
    try f.patch(2, [["op": "replace", "path": ["forkedFromId"], "value": UUID().uuidString]])
    #expect(f.session.sideParents.isEmpty)
    #expect(f.session.snapshot().counts?.processing == 1)
    let g = try SideFixture(); try g.activate(); try g.inventory([])
    #expect(g.session.sideParents.isEmpty)
    #expect(g.session.snapshot().counts?.processing == 0)
}

@Test func sideChatCandidateIsBoundedExpiresAndWaitsForAWindow() throws {
    let f = try SideFixture()
    try f.hint(viewer: "owner", method: "thread-stream-following-status-requested")
    try f.owner(f.side); try f.snapshot()
    #expect(f.session.snapshot().counts?.processing == 1)
    #expect(f.session.threads.snapshotDeadlines[f.side] == nil)
    try f.hint(); try f.session.refreshSideChats()
    #expect(f.session.snapshot().counts?.processing == 2)
    for _ in 0..<100 { try f.hint(UUID().uuidString) }
    #expect(f.session.sideCandidates.count == 63)
    f.clock.now += 31; try f.session.refreshSideChats()
    #expect(f.session.sideCandidates.isEmpty)
    #expect(f.session.sideParents.count == 1)
}

@Test func sideChatReconnectDropsOldDataAndReacquiresReplay() throws {
    let f = try SideFixture(); try f.activate()
    f.session.failRealtime(DesktopFailure.unavailable)
    #expect(f.session.sideParents.isEmpty)
    #expect(f.session.sideViewers.isEmpty)
    #expect(f.session.snapshot().counts == nil)
    f.session.socket = f.transport; f.session.client = "reconnected"
    try f.activate()
    #expect(f.session.snapshot().counts?.processing == 1)
    #expect(f.publications.alerts.isEmpty)
}

@Test func sideChatUnknownHintsNeverAcceptSelfRemoteOrFalseFollows() throws {
    let f = try SideFixture()
    try f.hint(viewer: "observer"); try f.hint(host: "remote"); try f.hint(following: false)
    #expect(f.session.sideCandidates.isEmpty)
    #expect(f.session.sideViewers.isEmpty)
}

@Test func newlyPersistedMainChatLeavesCandidatePathWithoutLosingStream() throws {
    let f = try SideFixture(); try f.hint(); try f.owner(f.side)
    try f.inventory([f.root, f.side])
    #expect(f.session.sideCandidates.isEmpty)
    #expect(f.session.threads.owners[f.side] == "owner")
    try f.snapshot(side: false, ephemeral: false)
    #expect(f.session.snapshot().counts?.processing == 2)
}

@Test func hiddenSideChatKeepsRunningUntilOwnerConfirmsDiscarded() throws {
    let f = try SideFixture(); try f.activate(); try f.hint(following: false)
    f.clock.now += 3; try f.session.refreshSideChats()
    #expect(f.session.snapshot().counts?.processing == 2)
    try f.patch(2, [["op": "replace", "path": ["threadRuntimeStatus", "activeFlags"], "value": ["waitingOnUserInput"]]])
    #expect(f.session.snapshot().counts?.waiting == 1)
    #expect(f.publications.alerts.last?.transition.kind == .waiting)
    try f.session.request(f.side)
    let key = try #require(f.transport.sent.last?["requestId"] as? String)
    try f.handle(["type": "response", "requestId": key, "resultType": "error", "error": "no-client-found"])
    #expect(f.session.sideParents.isEmpty)
    #expect(f.session.snapshot().counts?.processing == 1)
}
