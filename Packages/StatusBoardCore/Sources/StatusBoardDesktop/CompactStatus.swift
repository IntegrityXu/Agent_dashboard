import StatusBoardCore

public enum CompactStatus: String, Sendable {
    case waiting, done
    /// Initial snapshots have no observed event order. Keep a deterministic
    /// baseline until a live transition supplies recency.
    public static func baseline(_ counts: TaskCounts?) -> Self? {
        guard let counts else { return nil }
        return counts.waiting > 0 ? .waiting : counts.done > 0 ? .done : nil
    }
}

/// Recency belongs to individual outstanding tasks, not changing totals. This
/// still detects a newer wait when one old wait clears and the count stays 1.
struct CompactStatusTracker {
    struct Entry { let run: String?; let kind: CompactStatus; let order: UInt64 }
    private var entries: [String: Entry] = [:]
    private var order: UInt64 = 0

    mutating func remove(_ id: String) { entries.removeValue(forKey: id) }

    mutating func observe(_ id: String, before: DesktopObservation?, after: DesktopObservation?, live: Bool) {
        guard let after else { return }
        if let entry = entries[id], entry.run != after.runID { entries.removeValue(forKey: id) }
        guard live, let before else { return } // Loading history is not a new event.
        let wasWaiting = Self.kind(before) == .waiting
        let isWaiting = Self.kind(after) == .waiting
        let differentRequest = !before.pendingRequestIDs.isEmpty && !after.pendingRequestIDs.isEmpty
            && before.pendingRequestIDs.isDisjoint(with: after.pendingRequestIDs)
        let event: CompactStatus?
        if isWaiting && (!wasWaiting || before.runID != after.runID || differentRequest) { event = .waiting }
        else if after.status == "completed" && (before.status != "completed" || before.runID != after.runID) { event = .done }
        else { event = nil }
        if let event {
            order += 1
            entries[id] = Entry(run: after.runID, kind: event, order: order)
        }
    }

    func status(observations: [String: DesktopObservation], counts: TaskCounts?) -> CompactStatus? {
        guard let counts else { return nil }
        var newest: Entry?
        for (id, observation) in observations {
            guard let kind = Self.kind(observation), let entry = entries[id],
                  entry.run == observation.runID, entry.kind == kind,
                  (kind == .waiting ? counts.waiting : counts.done) > 0 else { continue }
            if newest == nil || entry.order > newest!.order { newest = entry }
        }
        return newest?.kind ?? CompactStatus.baseline(counts)
    }

    private static func kind(_ observation: DesktopObservation) -> CompactStatus? {
        switch LiveClassification.state(observation) {
        case .waitingUser, .waitingError: .waiting
        case .completed: observation.unread == true ? .done : nil
        default: nil
        }
    }
}
