import StatusBoardCore

enum OwnerDiscoveryResult: Equatable {
    case owner(String), unloaded, unavailable, incompatible

    init(_ response: WireValue) {
        if response["resultType"].string == "success",
           let owner = response["handledByClientId"].string, !owner.isEmpty {
            self = .owner(owner)
        } else if response["resultType"].string == "error", response["error"].string == "no-client-found" {
            self = .unloaded
        } else if response["resultType"].string == "success" || ["unsupported-version", "request-version-mismatch"].contains(response["error"].string ?? "") {
            self = .incompatible
        } else {
            // Request timeouts, disconnected clients, and malformed replies
            // do not establish that a thread is unloaded.
            self = .unavailable
        }
    }
}

/// New discovery cycles append missing work instead of replacing the tail.
/// Concurrency is bounded by the session; inventory scope is never truncated.
struct DiscoveryQueue {
    private var queue: [String] = []
    private var offset = 0
    private var queued = Set<String>()
    private var priority: [String] = []
    private var prioritized = Set<String>()

    mutating func enqueue(_ ids: Set<String>) {
        enqueueOrdered(ids.sorted())
    }

    mutating func enqueueOrdered(_ ids: [String]) {
        for id in ids where !prioritized.contains(id) && queued.insert(id).inserted { queue.append(id) }
    }

    /// Activity hints promote existing work without replacing the historical
    /// scan's unfinished tail. Only verified inventory IDs can be dispatched.
    mutating func prioritize(_ ids: [String]) {
        let promoted = Set(ids)
        queue = queue.dropFirst(offset).filter { !promoted.contains($0) }
        offset = 0; queued.subtract(promoted)
        for id in ids where prioritized.insert(id).inserted { priority.append(id) }
    }

    mutating func next(eligible: Set<String>, pending: Set<String>, allowBackground: Bool = true) -> String? {
        while !priority.isEmpty {
            let id = priority.removeFirst(); prioritized.remove(id)
            if eligible.contains(id) && !pending.contains(id) { return id }
        }
        guard allowBackground else { return nil }
        while offset < queue.count {
            let id = queue[offset]
            offset += 1
            queued.remove(id)
            if offset >= 256 && offset * 2 >= queue.count {
                queue.removeFirst(offset); offset = 0
            }
            if eligible.contains(id) && !pending.contains(id) { return id }
        }
        queue.removeAll(keepingCapacity: true); offset = 0
        return nil
    }
}
