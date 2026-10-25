import StatusBoardCore

/// Owner, stream, and snapshot deadline share one lifecycle. A timed-out live
/// source stays unavailable until discovery confirms that it has no owner.
struct ThreadTracking {
    private(set) var owners: [String: String] = [:]
    var streams: [String: DesktopStream] = [:]
    var snapshotDeadlines: [String: Double] = [:]
    private var readRefreshPending = Set<String>()
    private var unavailable = Set<String>()

    var observations: [String: DesktopObservation] { streams.compactMapValues(\.observation) }
    var recoveryBlocked: Set<String> { Set(streams.keys).union(unavailable) }

    /// A read change during an in-flight snapshot must survive that response.
    /// Repeated changes coalesce without extending the current timeout.
    mutating func needsReadSnapshot(_ id: String) -> Bool {
        guard owners[id] != nil else { return false }
        if snapshotDeadlines[id] != nil {
            readRefreshPending.insert(id)
            return false
        }
        return true
    }

    mutating func receivedSnapshot(_ id: String) -> Bool {
        snapshotDeadlines.removeValue(forKey: id)
        return readRefreshPending.remove(id) != nil
    }

    mutating func assign(_ id: String, owner: String) -> Bool {
        guard owners[id] != owner else { return false }
        remove(id, allowRecovery: false)
        owners[id] = owner
        streams[id] = DesktopStream(conversationID: id, hostID: "local")
        unavailable.remove(id)
        return true
    }

    mutating func remove(_ id: String, allowRecovery: Bool) {
        owners.removeValue(forKey: id)
        streams.removeValue(forKey: id)
        snapshotDeadlines.removeValue(forKey: id)
        readRefreshPending.remove(id)
        if allowRecovery { unavailable.remove(id) } else { unavailable.insert(id) }
    }
}
