import Foundation

extension DesktopStream {
    /// Validate only the status contract we consume. Additive fields are ignored
    /// by projection; changed required fields and new state values fail closed.
    public func validateCompatibility() throws {
        guard !needsSnapshot, let runtime = metadata["threadRuntimeStatus"]["type"].string,
              ["active", "idle", "systemError"].contains(runtime),
              metadata["requests"].array != nil,
              metadata["hasUnreadTurn"].bool != nil else { throw DesktopStreamError.malformed }
        // Only active runtime carries activeFlags; idle/systemError legitimately omit it.
        let flagValue = metadata["threadRuntimeStatus"]["activeFlags"]
        guard (runtime != "active" && flagValue == .null) || flagValue.array != nil else { throw DesktopStreamError.malformed }
        let flags = flagValue.array ?? []
        // Additional flags may change waiting semantics; never silently count them as active.
        let knownFlags: Set<String> = ["waitingOnApproval", "waitingOnUserInput"]
        guard flags.allSatisfy({ knownFlags.contains($0.string ?? "") }) else { throw DesktopStreamError.malformed }
        func validateTurn(_ turn: WireValue) throws {
            guard let id = turn["turnId"].string, !id.isEmpty,
                  let status = turn["status"].string,
                  ["inProgress", "completed", "failed", "interrupted"].contains(status) else { throw DesktopStreamError.malformed }
        }
        if metadata["turnHistory"] != .null {
            guard metadata["turnHistory"]["kind"].string == "canonical",
                  metadata["turnHistory"]["history"]["islands"].array != nil,
                  metadata["turnHistory"]["history"]["entitiesByKey"].object != nil else { throw DesktopStreamError.malformed }
            let history = metadata["turnHistory"]["history"]
            if let island = history["islands"].array?.last, island["newerBoundary"]["status"].string == "exhausted" {
                guard let entries = island["entries"].array else { throw DesktopStreamError.malformed }
                if let latest = entries.last {
                    guard let key = latest["value"].string else { throw DesktopStreamError.malformed }
                    try validateTurn(history["entitiesByKey"][key])
                }
            }
        } else {
            guard let turns = metadata["turns"].array else { throw DesktopStreamError.malformed }
            if let latest = turns.last { try validateTurn(latest) }
        }
        guard let current = observation else { throw DesktopStreamError.malformed }
        if let status = current.status {
            guard ["inProgress", "completed", "failed", "interrupted"].contains(status),
                  current.runID?.isEmpty == false else { throw DesktopStreamError.malformed }
        } else if current.runID != nil { throw DesktopStreamError.malformed }
        guard !current.hasUnclassifiedRequests else { throw DesktopStreamError.malformed }
    }
}
