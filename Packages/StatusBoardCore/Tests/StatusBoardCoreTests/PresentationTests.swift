import Foundation
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private let epoch = Date(timeIntervalSince1970: 1_000)
private func good(_ account: String = "A", partial: Bool = false) -> LiveSnapshot {
    var s = LiveSnapshot()
    s.accountFingerprint = account; s.isConnected = true
    s.counts = TaskCounts(processing: 1, waiting: 1, done: 2)
    s.covered = 4; s.total = partial ? 10 : 4
    s.updatedAt = epoch; s.quotaUpdatedAt = epoch
    s.lastCompleteSyncAt = partial ? nil : epoch
    s.quota = [QuotaWindow(key: "weekly", durationMinutes: 10080, usedPercent: 82, resetAt: epoch.addingTimeInterval(10))!]
    return s
}
private func disconnected(_ account: String? = "A", at date: Date = epoch.addingTimeInterval(1)) -> LiveSnapshot {
    var s = LiveSnapshot(); s.accountFingerprint = account; s.updatedAt = date; return s
}

@Test func savedUsageFreezesAcrossDisconnectResetAndRepaints() {
    var state = DashboardPresentation(); state.receive(good())
    state.receive(disconnected())
    let later = epoch.addingTimeInterval(1000)
    #expect(state.visibleSnapshot(at: later) == nil)
    #expect(state.windows(at: later).first?.remaining == 18)
    #expect(state.connectionLabel(at: later) == "Disconnected · Saved usage")
    #expect(state.lastCompleteSyncAt == epoch)
    state.receive(disconnected(at: later))
    #expect(state.lastCompleteSyncAt == epoch)
    #expect(state.windows(at: later).first?.remaining == 18)
}

@Test func cachedValuesRequireVerifiedSameAccountEvenOnRestart() {
    var state = DashboardPresentation(); state.receive(good())
    var restart = DashboardPresentation(saved: state.saved)
    #expect(restart.windows(at: epoch).isEmpty)
    restart.receive(disconnected("B"))
    #expect(restart.windows(at: epoch).isEmpty)
    #expect(restart.lastCompleteSyncAt == nil)
    restart.receive(disconnected(nil))
    #expect(restart.windows(at: epoch).isEmpty)
    restart.receive(disconnected())
    #expect(restart.windows(at: epoch).first?.remaining == 18)
    #expect(restart.visibleSnapshot(at: epoch) == nil) // Never restore task counts.
}

@Test func partialCoverageCannotInventACompleteSyncTimestamp() {
    var state = DashboardPresentation(); state.receive(good(partial: true))
    #expect(state.visibleSnapshot(at: epoch)?.counts?.done == 2)
    #expect(state.lastCompleteSyncAt == nil)
    #expect(state.windows(at: epoch).count == 1)
}

@Test func shortFailuresHaveBoundedGraceAndSilentWorkerExpires() {
    var state = DashboardPresentation(); state.receive(good())
    state.receive(disconnected())
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(2)) != nil)
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(5)) == nil)
    state.receive(good())
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(11)) == nil)
    #expect(state.windows(at: epoch.addingTimeInterval(11)).count == 1)
}

@Test func accountChangeAndUnknownIdentityBypassFailureGrace() {
    var state = DashboardPresentation(); state.receive(good())
    state.receive(disconnected("B"))
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(2)) == nil)
    #expect(state.windows(at: epoch).isEmpty)
    state.receive(good())
    state.receive(disconnected(nil))
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(2)) == nil)
    #expect(state.connectionLabel(at: epoch) == "Disconnected")
}

@Test func failureGraceNeverResurrectsOrExtendsExpiredLiveData() {
    var state = DashboardPresentation(); state.receive(good())
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(11)) == nil)
    state.receive(disconnected(at: epoch.addingTimeInterval(12)))
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(12)) == nil)
    #expect(state.connectionLabel(at: epoch.addingTimeInterval(12)) == "Disconnected · Saved usage")
    state.receive(good())
    state.receive(disconnected(at: epoch.addingTimeInterval(9)))
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(9)) != nil)
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(11)) == nil)
}

@Test func restartReconnectsBeforeAnyConversationLoadsOrReceivesAMessage() {
    var state = DashboardPresentation()
    state.receive(good())
    state.receive(disconnected())
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(5)) == nil)

    // IPC and quota recovered, but Codex has not loaded any conversation yet.
    var restored = LiveSnapshot.session(initialized: true, observations: [], total: 67, unassigned: 29,
        quota: good().quota, quotaDate: epoch.addingTimeInterval(6), accountFingerprint: "A")
    restored.updatedAt = epoch.addingTimeInterval(6)
    state.receive(restored)
    #expect(state.connectionLabel(at: restored.updatedAt) == "Connected")
    #expect(state.visibleSnapshot(at: restored.updatedAt) != nil)
    #expect(state.visibleSnapshot(at: restored.updatedAt)?.counts == nil)
    #expect(state.windows(at: restored.updatedAt) == restored.quota)
    #expect(restored.lastCompleteSyncAt == nil)

    // Periodic healthy snapshots keep an idle desktop connected, without events.
    restored.updatedAt = epoch.addingTimeInterval(60)
    state.receive(restored)
    #expect(state.connectionLabel(at: restored.updatedAt) == "Connected")
    // A real source failure still expires the connected presentation.
    state.receive(disconnected(at: epoch.addingTimeInterval(61)))
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(65)) == nil)
}

@Test func connectionRequiresHandshakeButQuotaFailureDoesNotDisconnect() {
    for initialized in [false, true] {
        for quotaDate in [nil, epoch] as [Date?] {
            let snapshot = LiveSnapshot.session(initialized: initialized, observations: [], total: 0, unassigned: 0,
                quota: [], quotaDate: quotaDate, accountFingerprint: "A")
            let ready = initialized
            #expect(snapshot.isConnected == ready)
            #expect(snapshot.counts == (ready ? TaskCounts() : nil))
            #expect(snapshot.lastCompleteSyncAt == (ready ? quotaDate : nil))
        }
    }
}

@Test func usersWithinOneWorkspaceNeverShareLiveOrSavedPresentation() throws {
    let first = VerifiedIdentity(id: "workspace", namespace: "origin", readScope: .init(identityKey: "user-A"))
    let second = VerifiedIdentity(id: "workspace", namespace: "origin", readScope: .init(identityKey: "user-B"))
    #expect(first.fingerprint != second.fingerprint)
    #expect(first.fingerprint == VerifiedIdentity(id: "workspace", namespace: "origin", readScope: .init(identityKey: "user-A")).fingerprint)
    var state = DashboardPresentation()
    state.receive(good(first.fingerprint))
    let saved = try #require(state.saved)
    state.receive(disconnected(second.fingerprint))
    #expect(state.visibleSnapshot(at: epoch.addingTimeInterval(2)) == nil)
    #expect(state.windows(at: epoch.addingTimeInterval(2)).isEmpty)
    var restart = DashboardPresentation(saved: saved)
    restart.receive(disconnected(second.fingerprint))
    #expect(restart.verifiedSavedUsage == nil)
    restart.receive(disconnected(first.fingerprint))
    #expect(restart.verifiedSavedUsage == saved)
    // Concatenating identity components must not create ambiguous identities.
    let ambiguous = VerifiedIdentity(id: "inworkspace", namespace: "orig", readScope: first.readScope)
    #expect(first.fingerprint != ambiguous.fingerprint)
}
