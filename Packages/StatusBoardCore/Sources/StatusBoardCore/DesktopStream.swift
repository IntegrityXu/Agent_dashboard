import Foundation

// Private desktop protocol, verified on builds 21477 and 21828. This is an experimental
// per-thread runtime source, NOT an account-scoped task inventory. Its revisions
// do not order read-state changes. No caller may infer complete=true from it.
public enum WireValue: Equatable, Sendable, Codable {
    case object([String: WireValue]), array([WireValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([WireValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: WireValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> WireValue { object?[key] ?? .null }
    public var object: [String: WireValue]? { if case .object(let v) = self { v } else { nil } }
    public var array: [WireValue]? { if case .array(let v) = self { v } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var integer: Int? {
        guard case .number(let v) = self, v.isFinite, v.rounded() == v,
              abs(v) <= 9_007_199_254_740_991 else { return nil }
        return Int(v)
    }
}

public enum DesktopStreamError: Error { case malformed, oversize, revisionGap, unexpectedOwner }

// Retain only state needed for runtime projection. In particular text, commands,
// paths, prompts, tool arguments/results, and error messages never enter storage.
indirect enum MetadataRule: Sendable {
    case leaf, replyIDs, fields([String: MetadataRule]), list(MetadataRule), map(MetadataRule)
    func child(_ key: WireValue) throws -> MetadataRule? {
        switch self {
        case .leaf, .replyIDs: throw DesktopStreamError.malformed
        case .fields(let fields):
            guard let key = key.string else { throw DesktopStreamError.malformed }
            return fields[key]
        case .list(let rule):
            guard key.integer != nil else { throw DesktopStreamError.malformed }
            return rule
        case .map(let rule):
            guard key.string != nil else { throw DesktopStreamError.malformed }
            return rule
        }
    }
    func project(_ value: WireValue) -> WireValue {
        switch self {
        case .leaf:
            switch value { case .object, .array: return .null; default: return value }
        case .replyIDs:
            // Decode only the desktop's structured async-reply envelope. The
            // question/answer text never enters retained metadata or logs.
            guard let text = value.string else { return .array([]) }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "<send_user_message_question_reply>"
            let suffix = "</send_user_message_question_reply>"
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix),
                  let data = String(trimmed.dropFirst(prefix.count).dropLast(suffix.count)).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return .array([]) }
            let replies = (object as? [[String: Any]]) ?? (object as? [String: Any]).map { [$0] } ?? []
            guard !replies.isEmpty, replies.allSatisfy({ $0["questionItemId"] is String && $0["question"] is String && $0["answer"] is String }) else { return .array([]) }
            return .array(replies.compactMap { ($0["questionItemId"] as? String).map(WireValue.string) })
        case .fields(let fields):
            guard let obj = value.object else { return .null }
            return .object(obj.reduce(into: [:]) { out, entry in
                if let rule = fields[entry.key] { out[entry.key] = rule.project(entry.value) }
            })
        case .map(let rule): return value.object.map { .object($0.mapValues(rule.project)) } ?? .null
        case .list(let rule): return value.array.map { .array($0.map(rule.project)) } ?? .null
        }
    }
    static let input: MetadataRule = .fields(["type": .leaf, "text": .replyIDs])
    static let item: MetadataRule = .fields([
        "id": .leaf, "type": .leaf, "status": .leaf,
        "agentPath": .leaf, "agentThreadId": .leaf, "kind": .leaf,
        "questions": .list(.fields([:])), // Keep only cardinality, never copy.
        "content": .list(input), "input": .list(input)
    ])
    static let turn: MetadataRule = .fields([
        "turnId": .leaf, "status": .leaf, "automationKind": .leaf, "automationNotificationDecision": .leaf,
        "items": .list(item)
    ])
    static let root: MetadataRule = .fields([
        "id": .leaf, "hostId": .leaf, "parentThreadId": .leaf,
        "sideConversation": .leaf, "ephemeral": .leaf, "forkedFromId": .leaf,
        "hasUnreadTurn": .leaf, "resumeState": .leaf,
        "threadRuntimeStatus": .fields(["type": .leaf, "activeFlags": .list(.leaf)]),
        "requests": .list(.fields(["id": .leaf, "method": .leaf, "completed": .leaf,
                                  "params": .fields(["turnId": .leaf])])),
        "turns": .list(turn), "turnHistory": .fields([
            "kind": .leaf, "history": .fields([
                "generation": .leaf, "isComplete": .leaf, "entitiesByKey": .map(turn),
                "islands": .list(.fields(["id": .leaf,
                    "newerBoundary": .fields(["status": .leaf]),
                    "entries": .list(.fields(["value": .leaf]))]))])])
    ])
}

private extension WireValue {
    mutating func patch(path: ArraySlice<WireValue>, op: String, value: WireValue) throws {
        guard let key = path.first else { self = op == "remove" ? .null : value; return }
        let rest = path.dropFirst()
        if case .object(var obj) = self, let k = key.string {
            if rest.isEmpty {
                if op == "remove" { guard obj.removeValue(forKey: k) != nil else { throw DesktopStreamError.malformed } }
                else {
                    if op == "replace", obj[k] == nil { throw DesktopStreamError.malformed }
                    obj[k] = value
                }
            } else {
                guard var child = obj[k] else { throw DesktopStreamError.malformed }
                try child.patch(path: rest, op: op, value: value); obj[k] = child
            }
            self = .object(obj)
        } else if case .array(var list) = self, let i = key.integer, i >= 0 {
            if rest.isEmpty, op == "add", i <= list.count { list.insert(value, at: i) }
            else {
                guard list.indices.contains(i) else { throw DesktopStreamError.malformed }
                if rest.isEmpty, op == "remove" { list.remove(at: i) }
                else { try list[i].patch(path: rest, op: op, value: value) }
            }
            self = .array(list)
        } else { throw DesktopStreamError.malformed }
    }
}

public struct DesktopObservation: Equatable, Sendable {
    public var runID: String?
    public var status: String?
    public var runtime: String?
    public var activeFlags: Set<String>
    public var unread: Bool?
    public var pendingRequestIDs: Set<String>
    public var hasUnclassifiedRequests: Bool
    public var isHeartbeat: Bool
    public var hasLatestTurnCoverage = true
    public var agents: [AgentActivity] = []
    public var isWaitingForUser: Bool {
        !pendingRequestIDs.isEmpty || !activeFlags.isDisjoint(with: ["waitingOnUserInput", "waitingOnApproval"])
    }
    public init(runID: String?, status: String?, runtime: String?, activeFlags: Set<String>, unread: Bool?,
                pendingRequestIDs: Set<String>, hasUnclassifiedRequests: Bool, isHeartbeat: Bool,
                hasLatestTurnCoverage: Bool = true, agents: [AgentActivity] = []) {
        self.runID = runID; self.status = status; self.runtime = runtime; self.activeFlags = activeFlags
        self.unread = unread; self.pendingRequestIDs = pendingRequestIDs
        self.hasUnclassifiedRequests = hasUnclassifiedRequests; self.isHeartbeat = isHeartbeat
        self.hasLatestTurnCoverage = hasLatestTurnCoverage; self.agents = agents
    }
    // Latest-run unread coverage and inventory are established separately by
    // the account-scoped session coordinator.
}

public struct DesktopTransition: Equatable, Sendable {
    public let occurrence: String
    public let kind: AlertKind
    public let revision: UInt64
}

public struct DesktopStream: Sendable {
    public let conversationID: String
    public let hostID: String
    public private(set) var revision: Int?
    public private(set) var owner: String?
    public private(set) var metadata: WireValue = .null
    public private(set) var needsSnapshot = true
    public init(conversationID: String, hostID: String) {
        self.conversationID = conversationID; self.hostID = hostID
    }
    public mutating func invalidate() { needsSnapshot = true; revision = nil; owner = nil; metadata = .null }

    public var observation: DesktopObservation? {
        guard !needsSnapshot else { return nil }
        var turns = metadata["turns"].array ?? []
        var hasLatestTurnCoverage = true
        let history = metadata["turnHistory"]["history"]
        if metadata["turnHistory"]["kind"].string == "canonical" {
            // Only the newest island can establish the current turn. Never
            // infer recency from dictionary order or an older paginated island.
            if let island = history["islands"].array?.last,
               island["newerBoundary"]["status"].string == "exhausted" {
                turns = (island["entries"].array ?? []).map { entry in
                    entry["value"].string.map { history["entitiesByKey"][$0] } ?? .null
                }
                hasLatestTurnCoverage = turns.isEmpty || turns.last?["turnId"].string != nil
            } else {
                turns = []
                hasLatestTurnCoverage = false
            }
        }
        let turn = turns.last ?? .null
        var pending = Set<String>()
        var unclassified = false
        let waitingMethods: Set<String> = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval",
            "item/permissions/requestApproval", "item/tool/requestUserInput", "item/tool/requestOptionPicker"]
        for request in metadata["requests"].array ?? [] where request["completed"].bool != true {
            let method = request["method"].string ?? ""
            if waitingMethods.contains(method), let id = request["id"].string ?? request["id"].integer.map(String.init),
               let run = turn["turnId"].string, request["params"]["turnId"].string == run {
                pending.insert("\(run):\(method):\(id)")
            } else { unclassified = true }
        }
        // Codex 21477 tracks async questions separately from blocking requests
        // and runtime flags. Match its unansweredAsyncQuestions semantics.
        if turn["status"].string == "inProgress", let run = turn["turnId"].string {
            var questions = Set<String>(), answered = Set<String>()
            for item in turn["items"].array ?? [] {
                if item["type"].string == "agentMessage", let id = item["id"].string {
                    for index in (item["questions"].array ?? []).indices {
                        if let data = try? JSONSerialization.data(withJSONObject: ["request_user_input_async", id, index], options: [.withoutEscapingSlashes]),
                           let key = String(data: data, encoding: .utf8) { questions.insert(key) }
                    }
                }
                let content: [WireValue]?
                if item["type"].string == "userMessage" { content = item["content"].array }
                else if item["type"].string == "steeringUserMessage", item["status"].string == "accepted" { content = item["input"].array }
                else { content = nil }
                if let content, content.count == 1, content[0]["type"].string == "text" {
                    answered.formUnion((content[0]["text"].array ?? []).compactMap(\.string))
                }
            }
            pending.formUnion(questions.subtracting(answered).map { "\(run):async:\($0)" })
        }
        return DesktopObservation(runID: turn["turnId"].string, status: turn["status"].string,
            runtime: metadata["threadRuntimeStatus"]["type"].string,
            activeFlags: Set((metadata["threadRuntimeStatus"]["activeFlags"].array ?? []).compactMap(\.string)),
            unread: metadata["hasUnreadTurn"].bool, pendingRequestIDs: pending,
            hasUnclassifiedRequests: unclassified,
            isHeartbeat: turn["automationKind"].string == "heartbeat",
            hasLatestTurnCoverage: hasLatestTurnCoverage,
            agents: AgentActivity.project(turn["items"].array ?? []))
    }

    /// The transport must verify this sender against owner discovery first.
    /// Snapshots (including same-revision read refreshes) establish SILENT baselines.
    public mutating func accept(change: WireValue, owner sender: String) throws -> [DesktopTransition] {
        do { return try apply(change: change, sender: sender) }
        catch { invalidate(); throw error }
    }
    private mutating func apply(change: WireValue, sender: String) throws -> [DesktopTransition] {
        guard let next = change["revision"].integer, next >= 0, !sender.isEmpty else { throw DesktopStreamError.malformed }
        if change["type"].string == "snapshot" {
            let state = change["conversationState"]
            guard state["id"].string == conversationID, state["hostId"].string == hostID else { throw DesktopStreamError.malformed }
            if sender == owner, let revision, next < revision { return [] }
            metadata = MetadataRule.root.project(state)
            revision = next; owner = sender; needsSnapshot = false
            return []
        }
        guard change["type"].string == "patches", let patches = change["patches"].array,
              let base = change["baseRevision"].integer else { throw DesktopStreamError.malformed }
        guard sender == owner else { throw DesktopStreamError.unexpectedOwner }
        guard !needsSnapshot, let previous = revision else { throw DesktopStreamError.revisionGap }
        if next <= previous { return [] } // Replayed/stale runtime patch.
        guard base == previous, next == base + 1 else { throw DesktopStreamError.revisionGap }
        let before = observation
        var candidate = metadata
        for patch in patches {
            guard let path = patch["path"].array, let op = patch["op"].string,
                  ["add", "replace", "remove"].contains(op) else { throw DesktopStreamError.malformed }
            var rule: MetadataRule? = .root
            for key in path { rule = try rule?.child(key) }
            guard let rule else { continue } // Text-only deltas still advance revision.
            try candidate.patch(path: path[...], op: op, value: rule.project(patch["value"]))
        }
        guard candidate["id"].string == conversationID, candidate["hostId"].string == hostID else { throw DesktopStreamError.malformed }
        metadata = candidate; revision = next
        // Heartbeat notification decisions need a separate verified contract.
        // Suppress their candidate alerts until that mapping is qualified.
        guard let before, let after = observation, !after.isHeartbeat,
              before.hasLatestTurnCoverage, after.hasLatestTurnCoverage else { return [] }
        var events: [DesktopTransition] = []
        if let run = after.runID, before.runID == run {
            if before.status != "completed", (before.status == "inProgress" || before.runtime == "active"),
               after.status == "completed" {
                events.append(.init(occurrence: "\(conversationID):\(run):completed", kind: .completed, revision: UInt64(next)))
            }
            // Failure and the active -> stopped runtime transition may arrive
            // in different patches. Retrying while active must stay silent.
            let stoppedFailure = after.runtime == "systemError" || (after.status == "failed" && after.runtime != "active")
            let wasStoppedFailure = before.runtime == "systemError" || (before.status == "failed" && before.runtime != "active")
            if stoppedFailure && !wasStoppedFailure {
                events.append(.init(occurrence: "\(conversationID):\(run):failed", kind: .failed, revision: UInt64(next)))
            }
        }
        let wasWaiting = before.isWaitingForUser
        let isWaiting = after.isWaitingForUser
        if isWaiting && (!wasWaiting || before.runID != after.runID), let run = after.runID {
            // Request arrival and runtime flags can describe the same episode.
            // Emit once on entry, even when their patches arrive separately.
            let identity = after.pendingRequestIDs.sorted().first ?? "\(run):wait:\(sender):\(next)"
            events.append(.init(occurrence: "\(conversationID):\(identity)", kind: .waiting, revision: UInt64(next)))
        }
        return events
    }
}
