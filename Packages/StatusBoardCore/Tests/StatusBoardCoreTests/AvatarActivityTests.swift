import Foundation
import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private let avatarStart = Date(timeIntervalSince1970: 10_000)

@Test func avatarSleepsAtExactlyThirtyMinutesWithoutEvents() {
    let activity = AvatarActivity(now: avatarStart)
    #expect(!activity.isSleeping(at: avatarStart.addingTimeInterval(1799.999)))
    #expect(activity.isSleeping(at: avatarStart.addingTimeInterval(1800)))
}

@Test func avatarPollingQuotaWaitingAndUnreadCountsDoNotPreventSleep() {
    var activity = AvatarActivity(now: avatarStart)
    var snapshot = LiveSnapshot()
    snapshot.isConnected = true
    snapshot.counts = TaskCounts(waiting: 2, done: 3)
    for seconds in stride(from: 0, through: 1800, by: 60) {
        let now = avatarStart.addingTimeInterval(Double(seconds))
        snapshot.updatedAt = now
        snapshot.quotaUpdatedAt = now
        activity.receive(snapshot, at: now)
    }
    #expect(activity.isSleeping(at: avatarStart.addingTimeInterval(1800)))
}

@Test func avatarWakesOnActivityAndRepeatedEventDoesNotRestartTimer() {
    var activity = AvatarActivity(now: avatarStart)
    let event = avatarStart.addingTimeInterval(2000)
    #expect(activity.isSleeping(at: event))
    var snapshot = LiveSnapshot()
    snapshot.lastCodexActivityAt = event
    activity.receive(snapshot, at: event)
    #expect(!activity.isSleeping(at: event))
    // Reconnects and subsequent polls carry the same event timestamp.
    snapshot.updatedAt = event.addingTimeInterval(1800)
    activity.receive(snapshot, at: snapshot.updatedAt)
    #expect(activity.isSleeping(at: snapshot.updatedAt))
}

@Test func avatarRemainsAwakeForLongRunningTaskThenSleepsAfterIdle() {
    var activity = AvatarActivity(now: avatarStart)
    var snapshot = LiveSnapshot()
    snapshot.isConnected = true
    snapshot.counts = TaskCounts(processing: 1)
    for seconds in stride(from: 0, through: 3600, by: 60) {
        let now = avatarStart.addingTimeInterval(Double(seconds))
        snapshot.updatedAt = now
        activity.receive(snapshot, at: now)
        #expect(!activity.isSleeping(at: now))
    }
    snapshot.counts = TaskCounts()
    let end = avatarStart.addingTimeInterval(3601)
    snapshot.lastCodexActivityAt = end
    activity.receive(snapshot, at: end)
    #expect(!activity.isSleeping(at: end.addingTimeInterval(1799)))
    #expect(activity.isSleeping(at: end.addingTimeInterval(1800)))
}

@Test func avatarDoesNotStayAwakeFromStaleOrDisconnectedProcessing() {
    for connected in [true, false] {
        var activity = AvatarActivity(now: avatarStart)
        var snapshot = LiveSnapshot()
        snapshot.counts = TaskCounts(processing: 1)
        snapshot.isConnected = connected
        let now = avatarStart.addingTimeInterval(1800)
        snapshot.updatedAt = connected ? avatarStart : now
        activity.receive(snapshot, at: now)
        #expect(activity.isSleeping(at: now))
    }
}
