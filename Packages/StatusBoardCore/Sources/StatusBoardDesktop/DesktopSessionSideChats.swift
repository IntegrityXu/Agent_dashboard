import Foundation
import StatusBoardCore

extension DesktopSession {
    /// Existing windows replay their follows when an observer connects. New
    /// owners announce themselves too. Neither announcement establishes scope:
    /// probe a bounded candidate set, then verify the owner snapshot and ancestry.
    func handleSideChatHint(_ message: WireValue) throws {
        let p = message["params"], method = message["method"].string
        if method == "client-status-changed", message["version"].integer == 0,
           p["status"].string == "disconnected", let viewer = p["clientId"].string {
            for id in Array(sideViewers.keys) {
                sideViewers[id]?.remove(viewer)
                if sideViewers[id]?.isEmpty == true {
                    sideClosing[id] = now + 2
                    discovery.prioritize([id])
                }
            }
            return
        }
        guard message["version"].integer == 1, p["hostId"].string == "local",
              let id = p["conversationId"].string, UUID(uuidString: id) != nil,
              let sender = message["sourceClientId"].string, sender != client,
              method == "thread-stream-following-changed" || method == "thread-stream-following-status-requested",
              !ids.contains(id), !agentIDs.contains(id) else { return }
        let isFollow = method == "thread-stream-following-changed"
        if isFollow && p["following"].bool == false {
            guard sideViewers[id] != nil else { return }
            sideViewers[id]?.remove(sender)
            if sideViewers[id]?.isEmpty == true {
                sideClosing[id] = now + 2
                discovery.prioritize([id])
            }
            return
        }
        guard !isFollow || p["following"].bool == true else { return }
        guard sideRejected[id].map({ now >= $0 }) ?? true else { return }
        if sideCandidates[id] == nil && sideParents[id] == nil {
            guard sideCandidates.count + sideParents.count < 64 else { return }
            sideCandidates[id] = now + 30
            discovery.prioritize([id])
        }
        if isFollow {
            sideViewers[id, default: []].insert(sender)
            sideClosing.removeValue(forKey: id)
        }
    }

    func scopedSideParent(_ parent: String, excluding id: String) -> Bool {
        var cursor = parent, visited: Set<String> = [id]
        while visited.insert(cursor).inserted {
            if ids.contains(cursor) { return true }
            guard let next = sideParents[cursor] else { return false }
            cursor = next
        }
        return false
    }

    /// Only local, ephemeral side conversations forked from a verified account
    /// root are promoted. Subagents and arbitrary unknown broadcasts stay out.
    @discardableResult func validateSideChat(_ id: String) throws -> Bool {
        guard let stream = threads.streams[id], !stream.needsSnapshot else { return false }
        let m = stream.metadata
        guard m["sideConversation"].bool == true, m["ephemeral"].bool == true,
              m["parentThreadId"] == .null, let parent = m["forkedFromId"].string,
              UUID(uuidString: parent) != nil, scopedSideParent(parent, excluding: id),
              sideParents[id].map({ $0 == parent }) ?? true else {
            try forgetSideChat(id, rejected: true)
            return false
        }
        guard sideParents[id] != nil || sideViewers[id]?.isEmpty == false else { return false }
        if sideParents[id] == nil { log?.record(.discovery, event: "side_chat_verified") }
        sideParents[id] = parent
        sideCandidates.removeValue(forKey: id)
        return true
    }

    func refreshSideChats() throws {
        sideRejected = sideRejected.filter { now < $0.value }
        for (id, parent) in sideParents where !scopedSideParent(parent, excluding: id) || ids.contains(id) {
            try forgetSideChat(id)
        }
        for (id, deadline) in sideCandidates {
            if ids.contains(id) || agentIDs.contains(id) { try forgetSideChat(id) }
            else if now >= deadline { try forgetSideChat(id, rejected: true) }
            else if threads.streams[id]?.needsSnapshot == false { try validateSideChat(id) }
        }
        // A hidden tab can release its view interest while work continues. Keep
        // observing that run; owner discovery distinguishes a truly discarded chat.
        // Once idle, release our follow so it cannot prevent ephemeral cleanup.
        for (id, deadline) in sideClosing {
            if let observation = threads.observations[id],
               observation.runtime == "active" || observation.status == "inProgress" || observation.isWaitingForUser {
                sideClosing[id] = now + 2
            } else if now >= deadline { try forgetSideChat(id) }
        }
    }

    func forgetSideChat(_ id: String, rejected: Bool = false) throws {
        if !ids.contains(id) && !agentIDs.contains(id) { try removeThread(id, reason: .untracked) }
        if sideParents[id] != nil { log?.record(.discovery, event: "side_chat_released") }
        sideParents.removeValue(forKey: id); sideCandidates.removeValue(forKey: id)
        sideViewers.removeValue(forKey: id); sideClosing.removeValue(forKey: id)
        if rejected && sideRejected.count < 256 { sideRejected[id] = now + 30 }
    }
}
