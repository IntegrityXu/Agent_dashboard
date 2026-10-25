import StatusBoardCore

public struct ProcessingAgent: Identifiable, Equatable, Sendable {
    public let rootID: String
    public let threadID: String
    public let path: String
    public let state: AgentActivity.State
    public var id: String { rootID + ":" + threadID }
    public var name: String { path.split(separator: "/").last.map(String.init) ?? "agent" }
    public var label: String { name + state.suffix }
    public init(rootID: String, threadID: String, path: String, state: AgentActivity.State) {
        self.rootID = rootID; self.threadID = threadID; self.path = path; self.state = state
    }
}

enum ProcessingAgents {
    /// Each list belongs to a currently processing root. Terminal turns, lost
    /// coverage, and the next turn cannot retain an earlier run's agents.
    static func rows(roots: Set<String>, observations: [String: DesktopObservation],
                     stored: [String: [String: DesktopObservation]] = [:]) -> [ProcessingAgent] {
        var rows: [ProcessingAgent] = []
        for root in roots.sorted() {
            guard let observation = observations[root], LiveClassification.state(observation) == .processing,
                  !["completed", "failed", "interrupted"].contains(observation.status ?? "") else { continue }
            rows.append(ProcessingAgent(rootID: root, threadID: root, path: "/root", state: .running))
            var visited: Set<String> = [root]
            func appendChildren(_ parent: DesktopObservation, path: String) {
                for agent in parent.agents where agent.path.hasPrefix(path + "/") {
                    guard !roots.contains(agent.threadID), visited.insert(agent.threadID).inserted else { continue }
                    let recorded = observation.runID.flatMap { stored[$0]?[agent.threadID] }
                    let child = childObservation(live: observations[agent.threadID], recorded: recorded)
                    rows.append(ProcessingAgent(rootID: root, threadID: agent.threadID, path: agent.path,
                        state: child.map { childState($0, fallback: agent.state) } ?? agent.state))
                    if let child { appendChildren(child, path: agent.path) }
                }
            }
            if observation.hasLatestTurnCoverage { appendChildren(observation, path: "/root") }
        }
        return rows
    }

    private static func childObservation(live: DesktopObservation?, recorded: DesktopObservation?) -> DesktopObservation? {
        // A reused child can still have the preceding completed desktop turn
        // while its next turn has reached the store.
        if live?.status == "completed", recorded?.status == "inProgress", live?.runID != recorded?.runID {
            return recorded
        }
        return live ?? recorded
    }

    private static func childState(_ child: DesktopObservation, fallback: AgentActivity.State) -> AgentActivity.State {
        if child.isWaitingForUser { return .waiting }
        if child.status == "inProgress" || (child.runtime == "active" && child.status == nil) { return .running }
        switch child.status {
        case "completed": return .done
        case "interrupted": return .stopped
        case "failed": return .failed
        default: return fallback
        }
    }
}
