import Foundation
import StatusBoardCore

extension DesktopSession {
    func readIdentity() throws {
        if try VerifiedIdentity.read(rpc) != identity {
            // A new session clears all per-account subscriptions and cached quotas.
            throw DesktopFailure.identityChanged
        }
    }
    func applyInventory(_ result: Inventory) throws {
        inventoryAvailable = true
        let next = Set(result.ids)
        for id in ids.subtracting(next) { try removeThread(id, reason: .untracked) }
        // Inventory is newest-first. Sorting UUIDs instead delays the current
        // conversation behind minutes of unloaded-history owner discovery.
        discovery.enqueueOrdered(result.ids.filter { !ids.contains($0) })
        if let previous = inventoryActivity {
            if previous != result.activity { lastCodexActivityAt = Date() }
            discovery.prioritize(result.ids.filter {
                threads.owners[$0] == nil && previous[$0] != result.activity[$0]
            })
        }
        inventoryActivity = result.activity
        ids = next; total = result.total; unassigned = result.unassigned
        try refreshSideChats()
    }
    func applyRecovery(_ snapshot: ReadStoreInvalidator.Snapshot, unread: Set<String>, completed: Set<String>) throws {
        storedUnread = unread; storedCompleted = completed
        if snapshot.changed {
            nextOwners = 0
            for id in threads.owners.keys where threads.needsReadSnapshot(id) { try follow(id, true) }
        }
    }
    // Catch only data reads. Subscription/socket errors still reach the monitor.
    func refreshInventory() throws {
        let result: Inventory
        do { result = try inventory.read(account: identity.id) }
        catch { sourceFailures.failed(.inventory, error: error, now: now, log: log); return }
        sourceFailures.recovered(.inventory, now: now, log: log)
        try applyInventory(result)
    }
    func refreshRecovery() throws {
        nextStoredUnread = now + 5; readRefresh = nil
        let snapshot: ReadStoreInvalidator.Snapshot
        let unread: Set<String>
        do {
            if invalidator == nil { invalidator = try ReadStoreInvalidator(home: home) }
            guard let invalidator else { throw DesktopFailure.unavailable }
            snapshot = try invalidator.read()
            unread = try identity.readScope.unread(in: snapshot.state).intersection(ids)
        } catch {
            storedUnread = []; storedCompleted = []; invalidator?.previous = nil
            sourceFailures.failed(.readStore, error: error, now: now, log: log); return
        }
        sourceFailures.recovered(.readStore, now: now, log: log)
        let completed: Set<String>
        do { completed = try completions.read(candidates: ids) }
        catch {
            storedUnread = []; storedCompleted = []; invalidator?.previous = nil
            sourceFailures.failed(.completions, error: error, now: now, log: log); return
        }
        sourceFailures.recovered(.completions, now: now, log: log)
        try applyRecovery(snapshot, unread: unread, completed: completed)
    }
    func refreshIdentity() throws {
        failureStage = .identity
        do { try readIdentity() }
        catch {
            identityVerified = false; audioEvents = []
            sourceFailures.failed(.identity, error: error, now: now, log: log)
            nextIdentity = now + 5
            if (error as? DesktopFailure) == .identityChanged || Self.closedHelper(error)
                || sourceFailures.expired(.identity, now: now) { throw error }
            return
        }
        identityVerified = true; nextIdentity = now + 15
        sourceFailures.recovered(.identity, now: now, log: log)
    }
    static func closedHelper(_ error: Error) -> Bool {
        if let error = error as? StageFailure { return closedHelper(error.cause) }
        if case RPCFailure.closed = error { return true }
        return false
    }
    func refreshQuota() throws {
        failureStage = .quota
        do { try readQuota() }
        catch {
            sourceFailures.failed(.quota, error: error, now: now, log: log)
            nextQuota = now + 5
            if (error as? DesktopFailure) == .identityChanged || Self.closedHelper(error) { throw error }
            return
        }
        nextQuota = now + 60
        sourceFailures.recovered(.quota, now: now, log: log)
    }
    func refreshAgents() throws {
        let observations = threads.observations
        do {
            storedAgentObservations = try storedAgents.read(roots: observations.filter { taskIDs.contains($0.key) })
            sourceFailures.recovered(.agents, now: now, log: log)
        } catch {
            storedAgentObservations = [:]
            sourceFailures.failed(.agents, error: error, now: now, log: log)
        }
        let rows = ProcessingAgents.rows(roots: taskIDs, observations: observations, stored: storedAgentObservations)
        let next = Set(rows.map(\.threadID)).subtracting(taskIDs)
        for id in agentIDs.subtracting(next) { try removeThread(id, reason: .untracked) }
        discovery.enqueue(next.subtracting(agentIDs))
        agentIDs = next
    }
    func readQuota() throws {
        let result = try rpc.request("account/rateLimits/read", [:])
        guard let account = result["accountId"] as? String else { throw DesktopFailure.unavailable }
        guard account == identity.id else { throw DesktopFailure.identityChanged }
        quota = try QuotaDecoder.decode(result)
        quotaDate = Date()
    }
}
