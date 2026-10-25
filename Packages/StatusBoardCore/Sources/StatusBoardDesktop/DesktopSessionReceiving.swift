import Foundation
import StatusBoardCore

extension DesktopSession {
    /// Only the realtime channel reconnects; identity, quota and stores keep their schedules.
    func pollRealtime() {
        do {
            if socket == nil {
                guard now >= nextRealtime else { Thread.sleep(forTimeInterval: 0.1); return }
                failureStage = .socket
                socket = try makeTransport()
            }
            if client == "initializing-client" && !requests.values.contains(where: { $0.thread == nil }) {
                try request(nil)
            }
            guard socket != nil else { return }
            let receiving = try receiveMessages()
            if !receiving { try expireRequests() }
        } catch { failRealtime(error) }
    }
    func sendRealtime(_ message: [String: Any]) {
        do { try socket?.send(message) }
        catch { failRealtime(error) }
    }
    func failRealtime(_ error: Error) {
        let wasConnected = client != "initializing-client"
        sourceFailures.failed(.socket, error: error, now: now, log: log)
        socket = nil; client = "initializing-client"
        audioEvents = []; invalidatedAudioThreads.formUnion(taskIDs)
        // Keep previously live conversations blocked from old disk recovery until
        // discovery confirms them unloaded or a fresh owner snapshot arrives.
        for id in threads.owners.keys { threads.remove(id, allowRecovery: !ids.contains(id)) }
        sideParents = [:]; sideCandidates = [:]; sideViewers = [:]; sideClosing = [:]; sideRejected = [:]
        requests = [:]; lateRequests = [:]; receiveBacklogSince = nil
        compactStatus = CompactStatusTracker(); storedAgentObservations = [:]
        discovery = DiscoveryQueue(); nextOwners = 0
        nextRealtime = now + realtimeBackoff.nextDelay(afterHealthySession: wasConnected)
        emit()
    }

    /// Drain ready bytes in bounded batches before expiring requests. Partial
    /// frames or a busy socket get one bounded grace period, never a sliding
    /// deadline that a stalled/continuous sender can renew forever.
    func receiveMessages() throws -> Bool {
        guard let socket else { return false }
        let started = now
        var reads = 0
        repeat {
            failureStage = .socket
            for message in try socket.receive(timeout: reads == 0 ? 100 : 0) { try handle(message) }
            reads += 1
        } while !cancelled() && socket.hasPendingBytes && reads < 16 && now - started < 0.05

        guard socket.hasPendingBytes || socket.hasPartialFrame else {
            receiveBacklogSince = nil
            return false
        }
        if receiveBacklogSince == nil { receiveBacklogSince = now }
        return now - (receiveBacklogSince ?? now) < 15
    }
}
