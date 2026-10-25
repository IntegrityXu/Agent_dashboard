import Foundation

/// Names and lifecycle metadata only; no prompts or command contents.
public struct AgentActivity: Equatable, Sendable {
    public enum State: String, Sendable {
        case running, done, stopped, waiting, failed, unknown
        public var suffix: String {
            switch self {
            case .running: "....."
            case .done: " done"
            case .stopped: " stopped"
            case .waiting: " waiting"
            case .failed: " failed"
            case .unknown: " —"
            }
        }
    }
    public let threadID: String
    public let path: String
    public var state: State
    public init(threadID: String, path: String, state: State) {
        self.threadID = threadID; self.path = path; self.state = state
    }
    public var name: String { path.split(separator: "/").last.map(String.init) ?? "agent" }

    public static func project(_ items: [WireValue]) -> [AgentActivity] {
        var agents: [AgentActivity] = []
        var indices: [String: Int] = [:]
        for item in items where item["type"].string == "subAgentActivity" {
            guard let id = item["agentThreadId"].string, UUID(uuidString: id) != nil,
                  let path = item["agentPath"].string, path.hasPrefix("/root/"),
                  path.count <= 1024, let kind = item["kind"].string else { continue }
            let state: State?
            switch kind {
            case "started": state = .running
            case "completed": state = .done
            case "interrupted": state = .stopped
            case "interacted": state = nil // A message alone does not restart a finished agent.
            default: continue
            }
            if let index = indices[id] {
                if let state { agents[index].state = state }
            } else {
                indices[id] = agents.count
                agents.append(AgentActivity(threadID: id, path: path, state: state ?? .unknown))
            }
        }
        return agents
    }
}
