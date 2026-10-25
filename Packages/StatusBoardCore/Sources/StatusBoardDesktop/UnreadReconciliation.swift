import StatusBoardCore

/// Read changes do not advance the desktop stream revision or reliably produce
/// a file change (a rapid unread/read round trip can have the same digest).
/// Recheck only Done contributors, using owner snapshots, never elapsed time
/// as evidence that a result was read. Times are monotonic system uptime.
struct UnreadReconciliation {
    private var deadlines: [String: Double] = [:]

    mutating func due(observations: [String: DesktopObservation], pending: Set<String>, now: Double) -> [String] {
        let candidates = Set(observations.compactMap { id, observation in
            LiveClassification.state(observation) == .completed && observation.unread == true ? id : nil
        })
        deadlines = deadlines.filter { candidates.contains($0.key) }
        var result: [String] = []
        for id in candidates.sorted() {
            // Revalidate initial/restored Done promptly, then at a bounded rate.
            guard let deadline = deadlines[id] else { deadlines[id] = now + 1; continue }
            guard now >= deadline, !pending.contains(id) else { continue }
            result.append(id)
            deadlines[id] = now + 5
        }
        return result
    }
}
