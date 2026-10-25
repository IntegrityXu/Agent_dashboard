import Foundation
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

@Test func arbitraryBuildMetadataIsDiagnosticAndReadFreshAfterUpdate() throws {
    let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: app) }
    #expect(DesktopCompatibility.build(applicationURL: app) == nil)
    for build in ["21477", "21828", "21829", "21828.1", "99999", ""] {
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": build], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        #expect(DesktopCompatibility.build(applicationURL: app) == build)
    }
}

@Test func protocolAndTransportFailuresHaveDistinctPresentation() {
    let protocolFailure = LiveSnapshot.failure(DesktopFailure.unsupported)
    #expect(protocolFailure.compatibilityIssue == .incompatibleProtocol)
    #expect(protocolFailure.message.contains("protocol or data format"))
    var presentation = DashboardPresentation()
    presentation.receive(protocolFailure)
    #expect(presentation.connectionLabel(at: protocolFailure.updatedAt) == "Incompatible Codex data")
    for error in [DesktopFailure.timeout, .unavailable, .unsafePath] {
        let failure = LiveSnapshot.failure(error)
        #expect(failure.compatibilityIssue == nil)
        #expect(failure.message == "Disconnected · retrying")
        presentation.receive(failure)
        #expect(presentation.connectionLabel(at: failure.updatedAt) == "Disconnected")
    }
    #expect(LiveSnapshot.failure(DesktopStreamError.oversize).message.contains("safety limit"))
}

@Test func incompatibilityImmediatelyHidesStaleCountsAndRecoversAfterSuccessfulConnection() {
    let now = Date()
    var healthy = LiveSnapshot()
    healthy.accountFingerprint = "fixture-account"; healthy.isConnected = true
    healthy.counts = TaskCounts(processing: 1, waiting: 0, done: 0)
    healthy.quota = [QuotaWindow(key: "weekly", durationMinutes: 10080, usedPercent: 30, resetAt: nil)!]
    healthy.quotaUpdatedAt = now; healthy.updatedAt = now
    var presentation = DashboardPresentation()
    presentation.receive(healthy)
    var failure = LiveSnapshot.failure(DesktopFailure.unsupported)
    failure.accountFingerprint = healthy.accountFingerprint // Same verified account may keep saved quota.
    failure.updatedAt = now.addingTimeInterval(1)
    presentation.receive(failure)
    #expect(presentation.visibleSnapshot(at: failure.updatedAt) == nil)
    #expect(presentation.windows(at: failure.updatedAt).first?.remaining == 70)
    #expect(presentation.connectionLabel(at: failure.updatedAt) == "Incompatible Codex data")
    // Failed account verification must hide cached quota too.
    presentation.receive(.failure(DesktopFailure.unavailable))
    #expect(presentation.windows(at: now).isEmpty)
    healthy.updatedAt = now.addingTimeInterval(2)
    presentation.receive(healthy)
    #expect(presentation.connectionLabel(at: healthy.updatedAt) == "Connected")
    #expect(presentation.visibleSnapshot(at: healthy.updatedAt)?.counts?.processing == 1)
}

@Test func realtimeFailureNeverShowsPreviousCountsWhenQuotaAlsoFails() {
    var presentation = DashboardPresentation()
    var healthy = LiveSnapshot()
    healthy.accountFingerprint = "same-account"; healthy.isConnected = true
    healthy.counts = TaskCounts(processing: 1)
    healthy.quota = [QuotaWindow(key: "week", durationMinutes: 10080, usedPercent: 40, resetAt: nil)!]
    healthy.quotaUpdatedAt = Date()
    presentation.receive(healthy)
    var failed = LiveSnapshot()
    failed.accountFingerprint = healthy.accountFingerprint
    failed.features = [.tasks: FeatureStatus(.incompatible, "Unsupported"), .quota: FeatureStatus(.saved, "Saved usage")]
    presentation.receive(failed)
    #expect(presentation.visibleSnapshot(at: failed.updatedAt) == nil)
    #expect(presentation.windows(at: failed.updatedAt).first?.remaining == 60)
}
