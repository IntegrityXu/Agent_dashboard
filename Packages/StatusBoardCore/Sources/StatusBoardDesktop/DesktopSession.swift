import Foundation
import StatusBoardCore

final class DesktopSession {
    struct Pending { let thread: String?; let deadline: Double }
    var socket: (any DesktopTransport)?
    let makeTransport: () throws -> any DesktopTransport
    let home: URL
    let codexBuild: String?
    var invalidator: ReadStoreInvalidator?
    var nextRealtime = 0.0
    var realtimeBackoff = ReconnectBackoff()
    let inventory: LocalInventory
    let completions: StoredCompletions
    let storedAgents: StoredAgentActivity
    var storedAgentObservations: [String: [String: DesktopObservation]] = [:]
    let identity: VerifiedIdentity
    let rpc: any DesktopRPC
    let uptime: () -> Double
    let cancelled: () -> Bool
    let refresh: () -> Bool
    let publish: @Sendable (LiveSnapshot) -> Void
    let audioGeneration = UUID()
    var audioEvents: [LiveAlert] = []
    var invalidatedAudioThreads = Set<String>()
    let log: DiagnosticLog?
    var receiveBacklogSince: Double?
    var streamIssues = Set<String>()
    var sourceFailures = SourceFailures()
    var identityVerified = true
    var inventoryAvailable = false
    var failureStage: DiagnosticStage = .handshake
    var client = "initializing-client"
    var ids = Set<String>()
    var inventoryActivity: [String: Inventory.Activity]?
    var titles: [String: String] = [:]
    var lastCodexActivityAt: Date?
    // Descendants are observed for the inline list only, never task counts or audio.
    var agentIDs = Set<String>()
    var sideParents: [String: String] = [:]
    var sideCandidates: [String: Double] = [:]
    var sideViewers: [String: Set<String>] = [:]
    var sideClosing: [String: Double] = [:]
    var sideRejected: [String: Double] = [:]
    var taskIDs: Set<String> { ids.union(sideParents.keys) }
    var followedIDs: Set<String> { taskIDs.union(agentIDs).union(sideCandidates.keys) }
    var total = 0, unassigned = 0
    var threads = ThreadTracking()
    var compactStatus = CompactStatusTracker()
    var requests: [String: Pending] = [:]
    // Keep timed-out request IDs briefly so a late reply can resolve an unknown
    // owner. A new request or removal invalidates the older generation.
    var lateRequests: [String: Pending] = [:]
    var discovery = DiscoveryQueue()
    var quota: [QuotaWindow] = []
    var quotaDate: Date?
    var nextIdentity = 0.0, nextInventory = 0.0, nextOwners = 0.0, nextQuota = 0.0, nextPublish = 0.0
    var readRefresh: Double?
    var unreadReconciliation = UnreadReconciliation()
    var storedCompleted = Set<String>()
    var storedUnread = Set<String>()
    var nextStoredUnread = 0.0
    var now: Double { uptime() }
    var isHealthy: Bool { identityVerified && (client != "initializing-client" || quotaDate != nil) }
    init(home: URL, rpc: any DesktopRPC, identity: VerifiedIdentity, cancelled: @escaping () -> Bool, refresh: @escaping () -> Bool,
         publish: @escaping @Sendable (LiveSnapshot) -> Void, transport: (any DesktopTransport)? = nil,
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, log: DiagnosticLog? = nil,
         codexBuild: String? = nil, transportFactory: (() throws -> any DesktopTransport)? = nil) throws {
        self.cancelled = cancelled; self.refresh = refresh; self.publish = publish
        self.rpc = rpc; self.identity = identity
        self.uptime = uptime; self.log = log
        self.home = home; self.codexBuild = codexBuild
        socket = transport
        makeTransport = transportFactory ?? { try DesktopSocket(home: home) }
        invalidator = try? ReadStoreInvalidator(home: home)
        inventory = LocalInventory(path: home.appendingPathComponent("state_5.sqlite").path)
        completions = StoredCompletions(path: home.appendingPathComponent("thread_history_1.sqlite").path)
        storedAgents = StoredAgentActivity(path: home.appendingPathComponent("thread_history_1.sqlite").path)
        nextIdentity = now + 15
    }
    func run() throws {
        defer {
            let originalStage = failureStage
            for id in threads.owners.keys { try? follow(id, false) }
            failureStage = originalStage
        }
        while !cancelled() {
            if refresh() { nextIdentity = 0; nextInventory = 0; nextQuota = 0; nextOwners = 0; nextStoredUnread = 0; nextRealtime = 0 }
            if now >= nextIdentity { try refreshIdentity() }
            if now >= nextInventory { try refreshInventory(); nextInventory = now + 5 }
            pollRealtime()
            try refreshSideChats()
            if now >= nextPublish { try refreshAgents() }
            if client != "initializing-client" {
                if now >= nextOwners { discovery.enqueue(followedIDs); nextOwners = now + 15 }
                try discoverOwners()
            }
            if invalidator?.drain() == true, readRefresh == nil {
                let retrying = sourceFailures.failures[.readStore] != nil || sourceFailures.failures[.completions] != nil
                readRefresh = retrying ? max(now + 0.25, nextStoredUnread) : now + 0.25
            }
            if now >= nextStoredUnread || readRefresh.map({ now >= $0 }) == true { try refreshRecovery() }
            for id in unreadReconciliation.due(observations: threads.observations,
                pending: Set(threads.snapshotDeadlines.keys), now: now) {
                try follow(id, true)
            }
            if now >= nextPublish { emit(); nextPublish = now + 1 }
            if now >= nextQuota {
                try refreshQuota()
            }
        }
    }
    func discoverOwners() throws {
        // Keep two of eight slots available for newly active conversations;
        // absent historical owners can occupy background slots for 15 seconds.
        while socket != nil, client != "initializing-client", requests.count < 8,
              let id = discovery.next(eligible: followedIDs, pending: Set(requests.values.compactMap(\.thread)),
                  allowBackground: requests.count < 6) {
            try request(id)
        }
    }
    enum RemovalReason { case untracked, unloaded, unavailable, invalidStream }
    func removeThread(_ id: String, reason: RemovalReason) throws {
        let allowRecovery: Bool
        switch reason {
        case .untracked, .unloaded:
            allowRecovery = true
            compactStatus.remove(id)
            if streamIssues.remove(id) != nil {
                log?.record(.stream, event: reason == .unloaded ? "unloaded" : "untracked")
            }
        case .unavailable: allowRecovery = !threads.recoveryBlocked.contains(id)
        case .invalidStream: allowRecovery = false
        }
        if threads.owners[id] != nil { invalidateAudio(id) }
        threads.remove(id, allowRecovery: allowRecovery)
        requests = requests.filter { $0.value.thread != id }
        lateRequests = lateRequests.filter { $0.value.thread != id }
        try follow(id, false)
    }
    func expireRequests() throws {
        lateRequests = lateRequests.filter { now <= $0.value.deadline }
        for (key, pending) in requests where now > pending.deadline {
            requests.removeValue(forKey: key)
            guard let id = pending.thread else { failureStage = .handshake; throw DesktopFailure.timeout }
            log?.record(.discovery, event: "timeout", error: DesktopFailure.timeout, throttled: true)
            // Unknown discovery is not evidence against a never-loaded thread's
            // verified disk baseline. Previously live threads remain blocked.
            try removeThread(id, reason: .unavailable)
            lateRequests[key] = Pending(thread: id, deadline: now + 30)
        }
        for (id, due) in threads.snapshotDeadlines where now > due {
            log?.record(.snapshot, event: "timeout", error: DesktopFailure.timeout, throttled: true)
            try removeThread(id, reason: .invalidStream)
        }
    }
    func request(_ thread: String?) throws {
        guard socket != nil else { return }
        let id = UUID().uuidString
        if let thread { lateRequests = lateRequests.filter { $0.value.thread != thread } }
        // Verified Codex builds permit 10s for router discovery, then 3s for the
        // forwarded request. Include 2s margin; initialize has no discovery.
        requests[id] = Pending(thread: thread, deadline: now + (thread == nil ? 5 : 15))
        failureStage = .socket
        sendRealtime(["type": "request", "requestId": id, "sourceClientId": client,
            "method": thread == nil ? "initialize" : "thread-owner-discovery", "version": thread == nil ? 0 : 1,
            "params": thread.map { ["hostId": "local", "conversationId": $0] } ?? ["clientType": "status-board-observer"], "timeoutMs": 3000])
    }
    func follow(_ id: String, _ value: Bool) throws {
        guard client != "initializing-client" else { return }
        failureStage = .socket
        sendRealtime(["type": "broadcast", "sourceClientId": client, "method": "thread-stream-following-changed", "version": 1,
            "params": ["hostId": "local", "conversationId": id, "following": value]])
        if value && socket != nil { threads.snapshotDeadlines[id] = now + 5 }
    }
    func handle(_ message: WireValue) throws {
        switch message["type"].string {
        case "client-discovery-request":
            guard let id = message["requestId"].string else { return }
            failureStage = .socket
            sendRealtime(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]])
        case "response": try handleResponse(message)
        case "broadcast": try handleBroadcast(message)
        default: break
        }
    }
    private func handleResponse(_ message: WireValue) throws {
        guard let key = message["requestId"].string else { return }
        let late = lateRequests.removeValue(forKey: key)
        guard let pending = requests.removeValue(forKey: key)
            ?? late.flatMap({ now <= $0.deadline ? $0 : nil }) else { return }
        guard let id = pending.thread else {
            failureStage = .handshake
            guard message["resultType"].string == "success" else { throw DesktopFailure.unavailable }
            guard let assigned = message["result"]["clientId"].string, !assigned.isEmpty else { throw DesktopFailure.unsupported }
            client = assigned
            realtimeBackoff = ReconnectBackoff()
            sourceFailures.recovered(.socket, now: now, log: log)
            log?.record(.handshake, event: "connected"); return
        }
        guard followedIDs.contains(id) else { return }
        switch OwnerDiscoveryResult(message) {
        case .owner(let owner):
            if threads.owners[id] != nil && threads.owners[id] != owner { invalidateAudio(id) }
            if threads.assign(id, owner: owner) { try follow(id, true) }
        case .unloaded:
            if sideParents[id] != nil || sideCandidates[id] != nil { try forgetSideChat(id) }
            else { try removeThread(id, reason: .unloaded) }
        case .incompatible:
            streamIssues.insert(id)
            try removeThread(id, reason: .invalidStream)
        case .unavailable: try removeThread(id, reason: .unavailable)
        }
    }
    private func handleBroadcast(_ message: WireValue) throws {
        let method = message["method"].string
        try handleSideChatHint(message)
        if method == "ipc-connection-reset" { failureStage = .socket; throw DesktopFailure.unavailable }
        let params = message["params"]
        if method == "thread-stream-following-status-requested", message["version"].integer == 1,
           params["hostId"].string == "local", let id = params["conversationId"].string {
            // A new owner announces that it needs follower subscriptions.
            // Treat this as a hint, never as proof of account scope/ownership.
            if !taskIDs.contains(id) && !agentIDs.contains(id) { nextInventory = 0 }
            guard followedIDs.contains(id) else { return }
            if let owner = threads.owners[id], owner == message["sourceClientId"].string {
                if threads.needsReadSnapshot(id) { try follow(id, true) }
            } else { discovery.prioritize([id]) }
            return
        }
        if method == "thread-stream-state-changed" { try handleStream(message, params: params) }
    }
    private func handleStream(_ message: WireValue, params: WireValue) throws {
        guard params["hostId"].string == "local",
              let id = params["conversationId"].string, followedIDs.contains(id) else { return }
        guard let sender = message["sourceClientId"].string, threads.owners[id] == sender else { return }
        guard message["version"].integer == 11 else {
            streamIssues.insert(id)
            log?.record(.stream, event: "unsupported_version_resync", error: DesktopFailure.unsupported,
                        version: message["version"].integer, throttled: true)
            try removeThread(id, reason: .invalidStream); return
        }
        do {
            let wasTask = taskIDs.contains(id)
            let before = threads.streams[id]?.observation
            let previousRevision = threads.streams[id]?.revision
            let events = try threads.streams[id]?.accept(change: params["change"], owner: sender) ?? []
            try threads.streams[id]?.validateCompatibility()
            if sideCandidates[id] != nil || sideParents[id] != nil {
                guard try validateSideChat(id) else {
                    if params["change"]["type"].string == "snapshot",
                       params["change"]["revision"].integer == threads.streams[id]?.revision {
                        _ = threads.receivedSnapshot(id)
                    }
                    return
                }
            }
            if (taskIDs.contains(id) || agentIDs.contains(id)),
               params["change"]["type"].string == "patches",
               let revision = threads.streams[id]?.revision,
               let previousRevision, revision > previousRevision {
                lastCodexActivityAt = Date()
            }
            if taskIDs.contains(id) {
                compactStatus.observe(id, before: before, after: threads.streams[id]?.observation,
                    live: params["change"]["type"].string == "patches")
            }
            if wasTask && taskIDs.contains(id) && isHealthy && !sourceFailures.expired(.inventory, now: now) && !cancelled() && !events.isEmpty {
                audioEvents += events.map { LiveAlert(thread: id, transition: $0, observedAt: Date()) }
                emit() // Preserve short events between periodic aggregate updates.
            }
        } catch {
            threads.streams[id]?.invalidate()
            streamIssues.insert(id)
            log?.record(.stream, event: "invalid_patch_resync", error: error, throttled: true)
            invalidateAudio(id)
            // accept already invalidated the stream. Repeated bad patches
            // must not extend the existing resnapshot timeout indefinitely.
            if threads.snapshotDeadlines[id] == nil { try follow(id, true) }
            return
        }
        if params["change"]["type"].string == "snapshot",
           params["change"]["revision"].integer == threads.streams[id]?.revision {
            if streamIssues.remove(id) != nil { log?.record(.stream, event: "recovered") }
            let refreshAgain = threads.receivedSnapshot(id)
            if refreshAgain { try follow(id, true) }
        }
    }
    func invalidateAudio(_ id: String) {
        guard taskIDs.contains(id) else { return }
        audioEvents.removeAll { $0.thread == id }
        invalidatedAudioThreads.insert(id)
        emit()
    }
    func emit() {
        guard !cancelled() else { return }
        publish(snapshot())
        audioEvents.removeAll(); invalidatedAudioThreads.removeAll()
    }
    func snapshot() -> LiveSnapshot {
        guard identityVerified else {
            var result = LiveSnapshot()
            result.message = "Verifying account · retrying"
            return result
        }
        let observations = threads.observations
        let restored = StoredCompletions.unloaded(storedCompleted, eligible: ids, liveThreads: threads.recoveryBlocked)
        var result = LiveSnapshot.session(initialized: client != "initializing-client",
            observations: observations.filter { taskIDs.contains($0.key) }.map(\.value), total: total + sideParents.count, unassigned: unassigned,
            restoredDone: restored.intersection(storedUnread).count, restoredCompleted: restored.count,
            quota: quota, quotaDate: quotaDate,
            accountFingerprint: identity.fingerprint)
        result.codexBuild = codexBuild
        result.lastCodexActivityAt = lastCodexActivityAt
        result.features = featureStatuses(covered: result.covered)
        // Quota remains live while IPC reconnects. Never keep task counts from a dead socket.
        result.isConnected = client != "initializing-client" || (quotaDate != nil && sourceFailures.failures[.quota] == nil)
        result.audioGeneration = audioGeneration
        result.audioEvents = audioEvents
        result.invalidatedAudioThreads = invalidatedAudioThreads
        result.compactStatus = compactStatus.status(observations: observations.filter { taskIDs.contains($0.key) }, counts: result.counts)
        if result.isConnected { result.agents = ProcessingAgents.rows(roots: taskIDs, observations: observations, stored: storedAgentObservations, titles: titles) }
        // A transient inventory failure preserves recent, verified scope.
        // Longer failures stop presenting stale counts as current data.
        if !inventoryAvailable && ids.isEmpty || sourceFailures.expired(.inventory, now: now) || sourceFailures.failures[.inventory]?.incompatible == true {
            result.counts = nil; result.agents = []; result.compactStatus = nil
            result.audioEvents = []; result.invalidatedAudioThreads.formUnion(taskIDs)
        }
        if result.features.values.contains(where: \.isDegraded) {
            result.lastCompleteSyncAt = nil
            result.message = result.featuresSummary
        }

        return result
    }
}
