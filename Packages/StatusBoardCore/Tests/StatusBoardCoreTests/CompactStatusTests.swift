import Testing
@testable import StatusBoardCore
@testable import StatusBoardDesktop

private func attention(_ state: String, run: String = "run", unread: Bool = true) -> DesktopObservation {
    DesktopObservation(runID: run, status: state == "waiting" ? "inProgress" : state,
        runtime: state == "completed" ? "idle" : "active",
        activeFlags: state == "waiting" ? ["waitingOnUserInput"] : [], unread: unread,
        pendingRequestIDs: [], hasUnclassifiedRequests: false, isHeartbeat: false)
}

@Test func compactStatusUsesNewestTaskEventInEitherDirection() {
    var tracker = CompactStatusTracker()
    let running = attention("inProgress"), waiting = attention("waiting"), done = attention("completed")
    tracker.observe("A", before: running, after: waiting, live: true)
    #expect(tracker.status(observations: ["A": waiting], counts: .init(waiting: 1)) == .waiting)
    tracker.observe("B", before: running, after: done, live: true)
    #expect(tracker.status(observations: ["A": waiting, "B": done], counts: .init(waiting: 1, done: 1)) == .done)
    // A cleared and C started waiting: the total remains one waiting task.
    tracker.observe("A", before: waiting, after: running, live: true)
    tracker.observe("C", before: running, after: waiting, live: true)
    #expect(tracker.status(observations: ["A": running, "B": done, "C": waiting], counts: .init(waiting: 1, done: 1)) == .waiting)
}

@Test func resolvedLatestTaskFallsBackToNewestOutstandingTaskThenClears() {
    var tracker = CompactStatusTracker()
    let running = attention("inProgress"), waiting = attention("waiting"), done = attention("completed")
    tracker.observe("old-done", before: running, after: done, live: true)
    tracker.observe("wait", before: running, after: waiting, live: true)
    tracker.observe("new-done", before: running, after: done, live: true)
    var observations = ["old-done": done, "wait": waiting, "new-done": done]
    #expect(tracker.status(observations: observations, counts: .init(waiting: 1, done: 2)) == .done)
    observations["new-done"] = attention("completed", unread: false)
    #expect(tracker.status(observations: observations, counts: .init(waiting: 1, done: 1)) == .waiting)
    observations["wait"] = running
    #expect(tracker.status(observations: observations, counts: .init(done: 1)) == .done)
    #expect(tracker.status(observations: observations, counts: .init()) == nil)
    #expect(tracker.status(observations: observations, counts: nil) == nil)
}

@Test func delayedUnreadAndReplayedSnapshotsDoNotReorderEvents() {
    var tracker = CompactStatusTracker()
    let running = attention("inProgress"), waiting = attention("waiting"), readDone = attention("completed", unread: false)
    tracker.observe("done", before: running, after: readDone, live: true)
    tracker.observe("wait", before: running, after: waiting, live: true)
    let unreadDone = attention("completed")
    tracker.observe("done", before: readDone, after: unreadDone, live: true)
    tracker.observe("done", before: unreadDone, after: unreadDone, live: false)
    tracker.observe("done", before: unreadDone, after: unreadDone, live: true)
    #expect(tracker.status(observations: ["done": unreadDone, "wait": waiting], counts: .init(waiting: 1, done: 1)) == .waiting)
}

@Test func newRunAndRemovedThreadCannotReusePreviousPriority() {
    var tracker = CompactStatusTracker()
    let running = attention("inProgress"), waiting = attention("waiting"), done = attention("completed")
    tracker.observe("wait", before: running, after: waiting, live: true)
    tracker.observe("done", before: running, after: done, live: true)
    let next = attention("completed", run: "new-run")
    tracker.observe("done", before: done, after: next, live: false)
    #expect(tracker.status(observations: ["done": next, "wait": waiting], counts: .init(waiting: 1, done: 1)) == .waiting)
    tracker.remove("wait")
    #expect(tracker.status(observations: [:], counts: .init(done: 1)) == .done)
    #expect(CompactStatusTracker().status(observations: [:], counts: .init(waiting: 1, done: 1)) == .waiting)
}

@Test func requestMetadataForExistingWaitDoesNotStealNewerDonePriority() {
    var tracker = CompactStatusTracker()
    let running = attention("inProgress"), waiting = attention("waiting"), done = attention("completed")
    tracker.observe("wait", before: running, after: waiting, live: true)
    tracker.observe("done", before: running, after: done, live: true)
    var request = waiting; request.pendingRequestIDs = ["question-1"]
    tracker.observe("wait", before: waiting, after: request, live: true)
    #expect(tracker.status(observations: ["wait": request, "done": done], counts: .init(waiting: 1, done: 1)) == .done)
    var next = waiting; next.pendingRequestIDs = ["question-2"]
    tracker.observe("wait", before: request, after: next, live: true)
    #expect(tracker.status(observations: ["wait": next, "done": done], counts: .init(waiting: 1, done: 1)) == .waiting)
}

@Test func heartbeatAndStoppedErrorsStillUpdateVisualBadge() {
    var tracker = CompactStatusTracker()
    var running = attention("inProgress"); running.isHeartbeat = true
    var done = attention("completed"); done.isHeartbeat = true
    tracker.observe("heartbeat", before: running, after: done, live: true)
    #expect(tracker.status(observations: ["heartbeat": done], counts: .init(done: 1)) == .done)
    var failed = attention("failed"); failed.runtime = "idle"
    tracker.observe("error", before: running, after: failed, live: true)
    #expect(tracker.status(observations: ["heartbeat": done, "error": failed], counts: .init(waiting: 1, done: 1)) == .waiting)
}
