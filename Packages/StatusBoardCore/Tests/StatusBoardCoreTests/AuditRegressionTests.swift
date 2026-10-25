import Foundation
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private final class AuditClock { var now = 100.0 }
private final class AuditRPC: DesktopRPC {
    var response: [String: Any] = [:]
    var delay: (() -> Void)?
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        delay?(); return response
    }
}
private final class AuditTransport: DesktopTransport {
    var hasPendingBytes: Bool { !chunks.isEmpty }
    var hasPartialFrame: Bool { decoder.hasPartialFrame }
    var sent: [[String: Any]] = []
    var chunks: [Data] = []
    var decoder = DesktopMetadataDecoder()
    var receives = 0
    var cancelAfter = 2
    func send(_ message: [String: Any]) throws { sent.append(message) }
    func receive(timeout: Int32) throws -> [WireValue] {
        receives += 1
        return chunks.isEmpty ? [] : try decoder.append(chunks.removeFirst())
    }
}
private final class AuditFixture {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let clock = AuditClock(), rpc = AuditRPC(), transport = AuditTransport()
    let id = UUID().uuidString
    let session: DesktopSession
    init() throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let clock = clock, transport = transport
        session = try DesktopSession(home: home, rpc: rpc,
            identity: .init(id: "account", namespace: "test", readScope: .init(identityKey: "user")),
            cancelled: { transport.receives >= transport.cancelAfter }, refresh: { false }, publish: { _ in },
            transport: transport, uptime: { clock.now })
        session.client = "observer"; session.ids = [id]; session.total = 1
        session.inventoryAvailable = true
        _ = session.threads.assign(id, owner: "owner")
        rpc.response = ["accountId": "account", "rateLimits": ["secondary": ["usedPercent": 40.0, "windowDurationMins": 10080] as [String: Any]]]
        try session.readQuota()
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    func wire(_ value: [String: Any]) throws -> WireValue {
        try JSONDecoder().decode(WireValue.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func stream(version: Int = 11, textBytes: Int = 0) -> [String: Any] {
        ["type": "broadcast", "method": "thread-stream-state-changed", "version": version,
         "sourceClientId": "owner", "params": ["hostId": "local", "conversationId": id,
            "change": ["type": "snapshot", "revision": 1, "conversationState": [
                "id": id, "hostId": "local", "hasUnreadTurn": false, "requests": [],
                "threadRuntimeStatus": ["type": "active", "activeFlags": []],
                "turns": [["turnId": "turn", "status": "inProgress", "items": [["type": "agentMessage", "text": String(repeating: "x", count: textBytes)]]]]]]]]
    }
}

@Test func auditMalformedQuotaMustRemainFailedAndRetainPreviousValue() throws {
    let f = try AuditFixture()
    f.rpc.response = ["accountId": "account", "rateLimits": "invalid-schema"]
    try f.session.refreshQuota()
    #expect(f.session.quota.first?.remaining == 60)
    #expect(f.session.sourceFailures.failures[.quota] != nil)
}

@Test func auditConfirmedUnloadedStreamMustClearRetryWarning() throws {
    let f = try AuditFixture()
    try f.session.handle(f.wire(f.stream(version: 12)))
    try f.session.request(f.id)
    let key = try #require(f.transport.sent.last?["requestId"] as? String)
    try f.session.handle(f.wire(["type": "response", "requestId": key, "resultType": "error", "error": "no-client-found"]))
    #expect(!f.session.streamIssues.contains(f.id))
    #expect(!f.session.snapshot().message.contains("retrying conversation data"))
}

@Test func auditSlowReadMustNotExpireAlreadyBufferedLargeSnapshot() throws {
    let f = try AuditFixture()
    try f.session.follow(f.id, true) // Deadline at 105.
    let data = try JSONSerialization.data(withJSONObject: f.stream(textBytes: 90_000), options: [.sortedKeys])
    var length = UInt32(data.count).littleEndian
    var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
    f.transport.chunks = [Data(frame.prefix(65536)), Data(frame.dropFirst(65536))]
    // A synchronous quota read consumes its 5-second budget. Both chunks
    // are already buffered when the session resumes receiving the socket.
    f.rpc.delay = { f.clock.now += 5.1 }
    try f.session.refreshQuota()
    f.session.nextIdentity = .greatestFiniteMagnitude
    f.session.nextInventory = .greatestFiniteMagnitude
    f.session.nextOwners = .greatestFiniteMagnitude
    f.session.nextPublish = .greatestFiniteMagnitude
    f.session.nextStoredUnread = .greatestFiniteMagnitude
    try f.session.run()
    #expect(f.session.threads.owners[f.id] == "owner")
    #expect(f.session.snapshot().counts?.processing == 1)
}

@Test func auditVerifiedSavedQuotaSurvivesHandshakeBeforeQuotaFetch() throws {
    let f = try AuditFixture()
    let original = f.session.snapshot()
    var presentation = DashboardPresentation()
    presentation.receive(original)
    f.session.quota = []; f.session.quotaDate = nil
    presentation.receive(f.session.snapshot())
    #expect(presentation.windows(at: Date()).first?.remaining == 60)
}

@Test func auditReadyBacklogLargerThanOneBatchSurvivesAndDrainIsBounded() throws {
    let f = try AuditFixture()
    try f.session.follow(f.id, true)
    let data = try JSONSerialization.data(withJSONObject: f.stream(textBytes: 1_200_000))
    var length = UInt32(data.count).littleEndian
    var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
    f.transport.chunks = stride(from: 0, to: frame.count, by: 65536).map {
        Data(frame[$0..<min($0 + 65536, frame.count)])
    }
    f.transport.cancelAfter = Int.max
    f.clock.now += 6
    #expect(try f.session.receiveMessages())
    #expect(f.transport.receives == 16)
    #expect(f.session.threads.owners[f.id] != nil)
    #expect(try !f.session.receiveMessages())
    try f.session.expireRequests()
    #expect(f.session.snapshot().counts?.processing == 1)
}

@Test func auditPartialHeaderGraceExpiresWithoutRenewingForever() throws {
    let f = try AuditFixture()
    f.transport.cancelAfter = Int.max
    try f.session.follow(f.id, true)
    f.transport.chunks = [Data([128, 0])]
    f.clock.now += 6
    #expect(try f.session.receiveMessages())
    f.clock.now += 14
    #expect(try f.session.receiveMessages())
    f.clock.now += 1
    #expect(try !f.session.receiveMessages())
    try f.session.expireRequests()
    #expect(f.session.threads.owners[f.id] == nil)
}

@Test func auditMalformedQuotaVariantsDoNotPartiallyCommit() throws {
    let f = try AuditFixture()
    let before = f.session.quotaDate
    let malformed: [[String: Any]] = [
        [:], ["rateLimits": NSNull()],
        ["rateLimits": [:], "rateLimitsByLimitId": "wrong"],
        ["rateLimits": ["primary": "wrong"]],
        ["rateLimits": ["primary": ["usedPercent": true, "windowDurationMins": 60]]],
        ["rateLimits": ["primary": ["usedPercent": 101, "windowDurationMins": 60]]],
        ["rateLimits": ["primary": ["usedPercent": 1, "windowDurationMins": 0]]],
        ["rateLimits": ["primary": ["usedPercent": 1, "windowDurationMins": 60, "resetsAt": "wrong"]]],
        ["rateLimits": ["primary": ["usedPercent": 1, "windowDurationMins": 60], "secondary": ["usedPercent": "wrong"]]]
    ]
    for var response in malformed {
        response["accountId"] = "account"; f.rpc.response = response
        try f.session.refreshQuota()
        #expect(f.session.quota.first?.remaining == 60)
        #expect(f.session.quotaDate == before)
        #expect(f.session.sourceFailures.failures[.quota] != nil)
    }
}

@Test func auditValidEmptyAndNullableQuotaRemainDistinctFromNotFetched() throws {
    let legacy: [String: Any] = ["secondary": ["usedPercent": 40, "windowDurationMins": 10080]]
    #expect(try QuotaDecoder.decode(["rateLimits": legacy, "rateLimitsByLimitId": NSNull()]).first?.remaining == 60)
    #expect(try QuotaDecoder.decode(["rateLimits": legacy, "rateLimitsByLimitId": [:]]).isEmpty)
    #expect(try QuotaDecoder.decode(["rateLimits": legacy, "rateLimitsByLimitId": ["other": legacy]]).isEmpty)
    #expect(try QuotaDecoder.decode(["rateLimits": ["primary": NSNull(), "secondary": NSNull()]]).isEmpty)
    #expect(try QuotaDecoder.decode(["rateLimits": ["primary": ["usedPercent": 40, "windowDurationMins": NSNull()]]]).isEmpty)
    let f = try AuditFixture()
    var presentation = DashboardPresentation()
    presentation.receive(f.session.snapshot())
    f.rpc.response = ["accountId": "account", "rateLimits": [:]]
    try f.session.refreshQuota()
    presentation.receive(f.session.snapshot())
    #expect(presentation.windows(at: Date()).isEmpty)
    let saved = try #require(presentation.saved)
    let restored = try JSONDecoder().decode(SavedUsage.self, from: JSONEncoder().encode(saved))
    presentation = DashboardPresentation(saved: restored)
    f.session.quotaDate = nil
    presentation.receive(f.session.snapshot())
    #expect(presentation.windows(at: Date()).isEmpty)
}

@Test func auditSavedQuotaNeverCrossesUnverifiedOrChangedAccount() throws {
    let f = try AuditFixture()
    var presentation = DashboardPresentation()
    presentation.receive(f.session.snapshot())
    var next = f.session.snapshot()
    next.quota = []; next.quotaUpdatedAt = nil; next.accountFingerprint = nil
    presentation.receive(next)
    #expect(presentation.windows(at: Date()).isEmpty)
    next.accountFingerprint = "different-account"
    presentation.receive(next)
    #expect(presentation.windows(at: Date()).isEmpty)
}

@Test func auditTransientStreamLossPreservesIssueButUntrackingEndsIt() throws {
    let f = try AuditFixture()
    try f.session.handle(f.wire(f.stream(version: 12)))
    try f.session.removeThread(f.id, reason: .unavailable)
    #expect(f.session.streamIssues.contains(f.id))
    try f.session.removeThread(f.id, reason: .untracked)
    #expect(f.session.streamIssues.isEmpty)
}
