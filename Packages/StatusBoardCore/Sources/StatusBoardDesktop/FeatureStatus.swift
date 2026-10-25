import Foundation

public enum DesktopFeature: String, CaseIterable, Sendable {
    case tasks = "Live tasks"
    case quota = "Usage"
    case history = "History recovery"
    case agents = "Agent list"
}

public struct FeatureStatus: Equatable, Sendable {
    public enum State: String, Sendable { case available, checking, partial, unavailable, incompatible, saved }
    public let state: State
    public let detail: String
    public init(_ state: State, _ detail: String) { self.state = state; self.detail = detail }
    public var isDegraded: Bool { [.partial, .unavailable, .incompatible, .saved].contains(state) }
}

extension LiveSnapshot {
    public var featuresSummary: String {
        DesktopFeature.allCases.compactMap { feature in
            features[feature].map { "\(feature.rawValue): \($0.detail)" }
        }.joined(separator: "\n")
    }
}

extension DesktopSession {
    func featureStatuses(covered: Int) -> [DesktopFeature: FeatureStatus] {
        func failure(_ stages: [DiagnosticStage]) -> FeatureStatus? {
            let failures = stages.compactMap { sourceFailures.failures[$0] }
            if failures.contains(where: \.incompatible) {
                return FeatureStatus(.incompatible, "Unsupported data format · retrying; may need a Status Board update")
            }
            return failures.isEmpty ? nil : FeatureStatus(.unavailable, "Temporarily unavailable · retrying")
        }
        let scopeFailure = failure([.inventory])
        let taskIssues = streamIssues.intersection(taskIDs)
        let tasks: FeatureStatus
        if let issue = failure([.socket]) ?? scopeFailure { tasks = issue }
        else if !taskIssues.isEmpty {
            tasks = FeatureStatus(covered > 0 ? .partial : .incompatible,
                "\(taskIssues.count) conversation(s) unavailable · rechecking protocol and data")
        } else if client == "initializing-client" || covered == 0 && total > 0 {
            tasks = FeatureStatus(.checking, "Waiting for verified conversation data")
        } else { tasks = FeatureStatus(.available, "Available") }
        var usage = failure([.quota]) ?? FeatureStatus(quotaDate == nil ? .checking : .available,
            quotaDate == nil ? "Checking" : "Available")
        if usage.isDegraded && quotaDate != nil {
            usage = FeatureStatus(.saved, "Saved usage · " + usage.detail)
        }
        let history = scopeFailure ?? failure([.readStore, .completions])
            ?? FeatureStatus(nextStoredUnread == 0 ? .checking : .available, nextStoredUnread == 0 ? "Checking" : "Available")
        let agents: FeatureStatus
        if let issue = failure([.socket]) ?? scopeFailure { agents = issue }
        else if failure([.agents]) != nil || !streamIssues.intersection(agentIDs).isEmpty {
            agents = FeatureStatus(.partial, "Some agent data unavailable · retrying; verified live rows remain visible")
        } else { agents = FeatureStatus(.available, "Available for verified live tasks") }
        return [.tasks: tasks, .quota: usage, .history: history, .agents: agents]
    }
}
