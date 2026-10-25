import Foundation

/// Incremental IPC framing and JSON projection. Body bytes are consumed once;
/// only allowlisted metadata is retained, never a complete raw JSON frame.
public struct DesktopMetadataDecoder {
    // Codex build 21477's IPC transport limit, independent of retained memory.
    public static let wireLimit = 256 * 1024 * 1024
    public static let metadataLimit = 8 * 1024 * 1024
    private var header: [UInt8] = []
    private var remaining = 0
    private var parser: MetadataJSONParser?
    public private(set) var lastRetainedBytes = 0
    public var hasPartialFrame: Bool { !header.isEmpty || remaining > 0 }
    public init() {}

    public mutating func append(_ data: Data) throws -> [WireValue] {
        var messages: [WireValue] = []
        do {
            for byte in data {
                if remaining == 0 {
                    header.append(byte)
                    if header.count == 4 {
                        let size = header.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
                        header.removeAll(keepingCapacity: true)
                        guard size > 0, size <= Self.wireLimit else { throw DesktopStreamError.malformed }
                        remaining = size
                        parser = MetadataJSONParser(rule: .envelope)
                    }
                } else {
                    try parser!.consume(byte)
                    remaining -= 1
                    if remaining == 0 {
                        let value = try parser!.finish()
                        lastRetainedBytes = parser!.retainedBytes
                        messages.append(value)
                        parser = nil
                    }
                }
            }
            return messages
        } catch {
            header.removeAll(); remaining = 0; parser = nil
            throw error
        }
    }
}

private indirect enum JSONSelection: Sendable {
    case scalar, presence, reply, fields([String: JSONSelection]), list(JSONSelection), map(JSONSelection)
    case patch, patchRootValue, patchRootField(String), patchValue, replyEnvelope

    init(_ rule: MetadataRule) {
        switch rule {
        case .leaf: self = .scalar
        case .replyIDs: self = .reply
        case .fields(let fields): self = .fields(fields.mapValues(JSONSelection.init))
        case .list(let item): self = .list(JSONSelection(item))
        case .map(let item): self = .map(JSONSelection(item))
        }
    }
    static let envelope: JSONSelection = .fields([
        "type": .scalar, "requestId": .scalar, "sourceClientId": .scalar,
        "method": .scalar, "version": .scalar, "resultType": .scalar,
        "handledByClientId": .scalar, "error": .scalar,
        "result": .fields(["clientId": .scalar]),
        "params": .fields(["hostId": .scalar, "conversationId": .scalar,
            "following": .scalar, "clientId": .scalar, "status": .scalar,
            "change": .fields(["type": .scalar, "revision": .scalar, "baseRevision": .scalar,
                "conversationState": JSONSelection(MetadataRule.root), "patches": .list(.patch)])])
    ])
    static let replyFields: [String: JSONSelection] = ["questionItemId": .scalar, "question": .presence, "answer": .presence]
    static let metadataKeys: Set<String> = {
        func keys(_ rule: MetadataRule) -> Set<String> {
            switch rule {
            case .fields(let fields): return fields.values.reduce(Set(fields.keys)) { $0.union(keys($1)) }
            case .list(let item), .map(let item): return keys(item)
            case .leaf, .replyIDs: return []
            }
        }
        return keys(.root)
    }()

    func field(_ key: String, values: [String: WireValue]) throws -> JSONSelection? {
        switch self {
        case .fields(let fields): return fields[key]
        case .map(let item): return item
        case .replyEnvelope: return Self.replyFields[key]
        case .patch:
            if key == "op" { return .scalar }
            if key == "path" { return .list(.scalar) }
            guard key == "value" else { return nil }
            if let path = values["path"]?.array {
                var rule: MetadataRule? = .root
                do { for component in path { rule = try rule?.child(component) } }
                catch { return .patchValue } // Per-stream validation handles a bad path.
                return rule.map(JSONSelection.init)
            }
            // Until path arrives, the value may itself be entitiesByKey. Its
            // immediate keys can be arbitrary (even "text" or "questions").
            // Retain projected candidates within the same metadata budget;
            // accept() subsequently applies the exact path rule.
            return .patchRootValue
        case .patchRootValue:
            // An unknown key can only be a turn-map entry. Do not retain an
            // unrelated scalar or arbitrary nested object under that key.
            return Self.metadataKeys.contains(key) ? .patchRootField(key) : JSONSelection(MetadataRule.turn)
        case .patchValue:
            if key == "text" { return .reply }
            if key == "questions" { return .list(.fields([:])) }
            if key == "entitiesByKey" { return .map(.patchValue) }
            return Self.metadataKeys.contains(key) ? .patchValue : nil
        default: return nil
        }
    }
    var element: JSONSelection? {
        switch self {
        case .list(let item): return item
        case .patchRootValue, .patchValue: return .patchValue
        case .replyEnvelope: return .fields(Self.replyFields)
        default: return nil
        }
    }
    var retainsObject: Bool {
        switch self { case .fields, .map, .patch, .patchRootValue, .patchValue, .replyEnvelope: return true; default: return false }
    }
    var retainsArray: Bool { element != nil }

    func containerRule(object: Bool) -> JSONSelection {
        guard case .patchRootField(let key) = self else { return self }
        // Resolve ambiguous names by shape: "text" can be a map key holding a
        // turn object, but a string named "text" must still discard prose.
        if object { return key == "entitiesByKey" ? .map(.patchValue) : .patchValue }
        return key == "questions" ? .list(.fields([:])) : .patchValue
    }
}

/// A small SAX-style JSON reader. Skipped strings and containers are validated
/// structurally but do not allocate their payload. Arrays keep their positions,
/// because desktop patches address items by numeric index.
private final class MetadataJSONParser {
    enum State { case keyOrEnd, key, colon, value, valueOrEnd, commaOrEnd }
    final class Frame {
        let object: Bool
        let rule: JSONSelection?
        let retain: Bool
        var state: State
        var key: String?
        var selected: JSONSelection?
        var fields: [String: WireValue] = [:]
        var items: [WireValue] = []
        init(object: Bool, rule: JSONSelection?) {
            self.object = object; self.rule = rule?.containerRule(object: object)
            retain = object ? self.rule?.retainsObject == true : self.rule?.retainsArray == true
            state = object ? .keyOrEnd : .valueOrEnd
        }
    }
    let rule: JSONSelection
    var stack: [Frame] = []
    var root: WireValue?
    var complete = false
    var string: JSONStringReader?
    var readingKey = false
    var atom: [UInt8] = []
    var atomRule: JSONSelection?
    var readingAtom = false
    private(set) var retainedBytes = 0
    private var nodes = 0
    init(rule: JSONSelection) { self.rule = rule }

    func charge(_ count: Int) throws {
        retainedBytes += count
        guard retainedBytes <= DesktopMetadataDecoder.metadataLimit else { throw DesktopStreamError.oversize }
    }
    func valueRule() -> JSONSelection? {
        guard let frame = stack.last else { return rule }
        return frame.object ? frame.selected : frame.rule?.element
    }
    func consume(_ byte: UInt8) throws {
        if let string {
            if try string.consume(byte) {
                self.string = nil
                if readingKey {
                    guard let frame = stack.last else { throw DesktopStreamError.malformed }
                    frame.key = string.value?.string
                    frame.selected = try frame.key.flatMap { try frame.rule?.field($0, values: frame.fields) }
                    frame.state = .colon
                } else {
                    try finishValue(string.value)
                }
            }
            return
        }
        if readingAtom {
            if byte == 44 || byte == 93 || byte == 125 || Self.whitespace(byte) {
                try finishAtom()
                try consume(byte)
            } else {
                guard atom.count < 128 else { throw DesktopStreamError.malformed }
                atom.append(byte)
            }
            return
        }
        if Self.whitespace(byte) { return }
        guard !complete else { throw DesktopStreamError.malformed }
        if let frame = stack.last {
            switch frame.state {
            case .keyOrEnd, .key:
                if byte == 125, frame.state == .keyOrEnd { try closeContainer(object: true); return }
                guard byte == 34 else { throw DesktopStreamError.malformed }
                readingKey = true; string = JSONStringReader(kind: frame.retain ? .key : .discard)
                return
            case .colon:
                guard byte == 58 else { throw DesktopStreamError.malformed }
                frame.state = .value; return
            case .commaOrEnd:
                if byte == (frame.object ? 125 : 93) { try closeContainer(object: frame.object); return }
                guard byte == 44 else { throw DesktopStreamError.malformed }
                frame.state = frame.object ? .key : .value; return
            case .valueOrEnd:
                if byte == 93 { try closeContainer(object: false); return }
            case .value: break
            }
        }
        let selected = valueRule()
        switch byte {
        case 123, 91:
            guard stack.count < 128 else { throw DesktopStreamError.malformed }
            stack.append(Frame(object: byte == 123, rule: selected))
        case 34:
            readingKey = false
            string = JSONStringReader(kind: JSONStringReader.Kind(selected))
        case 45, 48...57, 116, 102, 110:
            readingAtom = true; atom = [byte]; atomRule = selected
        default: throw DesktopStreamError.malformed
        }
    }
    static func whitespace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
    func finishAtom() throws {
        let value = try JSONDecoder().decode(WireValue.self, from: Data(atom))
        switch value { case .null, .bool, .number: break; default: throw DesktopStreamError.malformed }
        readingAtom = false; atom.removeAll(keepingCapacity: true)
        try finishValue(atomRule == nil ? nil : value)
        atomRule = nil
    }
    func closeContainer(object: Bool) throws {
        guard let frame = stack.last, frame.object == object else { throw DesktopStreamError.malformed }
        stack.removeLast()
        let value: WireValue? = frame.retain ? (object ? .object(frame.fields) : .array(frame.items)) : (frame.rule == nil ? nil : .null)
        try finishValue(value)
    }
    func finishValue(_ value: WireValue?) throws {
        if let value {
            nodes += 1
            guard nodes <= 200_000 else { throw DesktopStreamError.oversize }
            switch value { case .string(let text): try charge(text.utf8.count + 16); default: try charge(16) }
        }
        guard let frame = stack.last else {
            root = value ?? .null; complete = true; return
        }
        if frame.retain {
            if frame.object {
                if let key = frame.key, frame.selected != nil {
                    try charge(key.utf8.count + 16)
                    frame.fields[key] = value ?? .null
                }
            } else { frame.items.append(value ?? .null) }
        }
        frame.key = nil; frame.selected = nil; frame.state = .commaOrEnd
    }
    func finish() throws -> WireValue {
        if readingAtom { try finishAtom() }
        guard string == nil, stack.isEmpty, complete, let root else { throw DesktopStreamError.malformed }
        return root
    }
}

/// Decodes JSON escapes a few bytes at a time. Unselected text is not buffered.
private final class JSONStringReader {
    enum Kind {
        case key, scalar, presence, reply, candidate, discard
        init(_ rule: JSONSelection?) {
            switch rule {
            case .scalar: self = .scalar
            case .presence: self = .presence
            case .reply: self = .reply
            case .patchRootValue, .patchValue: self = .candidate
            case .patchRootField(let key): self = key == "text" ? .reply : .candidate
            default: self = .discard
            }
        }
    }
    let kind: Kind
    var bytes: [UInt8] = []
    var overflow = false
    var escaping = false
    var unicodeDigits = 0
    var unicodeValue: UInt32 = 0
    var highSurrogate: UInt32?
    var reply: ReplyTextReader?
    private(set) var value: WireValue?
    init(kind: Kind) {
        self.kind = kind
        if kind == .reply || kind == .candidate { reply = ReplyTextReader() }
    }
    func output(_ byte: UInt8) throws {
        if let reply { try reply.consume(byte) }
        let limit = kind == .key ? 1024 : 65536
        if kind == .key || kind == .scalar || kind == .candidate {
            if bytes.count < limit && !overflow { bytes.append(byte) }
            else {
                if kind == .scalar { throw DesktopStreamError.oversize }
                overflow = true; bytes.removeAll(keepingCapacity: false)
            }
        }
    }
    func scalar(_ code: UInt32) throws {
        if let high = highSurrogate {
            guard (0xDC00...0xDFFF).contains(code), let scalar = UnicodeScalar(0x10000 + (high - 0xD800) * 1024 + code - 0xDC00) else { throw DesktopStreamError.malformed }
            highSurrogate = nil
            for byte in String(scalar).utf8 { try output(byte) }
        } else if (0xD800...0xDBFF).contains(code) { highSurrogate = code }
        else {
            guard let scalar = UnicodeScalar(code) else { throw DesktopStreamError.malformed }
            for byte in String(scalar).utf8 { try output(byte) }
        }
    }
    func consume(_ byte: UInt8) throws -> Bool {
        if unicodeDigits > 0 {
            let digit: UInt32
            switch byte { case 48...57: digit = UInt32(byte - 48); case 65...70: digit = UInt32(byte - 55); case 97...102: digit = UInt32(byte - 87); default: throw DesktopStreamError.malformed }
            unicodeValue = unicodeValue * 16 + digit; unicodeDigits -= 1
            if unicodeDigits == 0 { try scalar(unicodeValue) }
            return false
        }
        if escaping {
            escaping = false
            if byte == 117 { unicodeDigits = 4; unicodeValue = 0; return false }
            guard highSurrogate == nil else { throw DesktopStreamError.malformed }
            switch byte {
            case 34, 47, 92: try output(byte)
            case 98: try output(8)
            case 102: try output(12)
            case 110: try output(10)
            case 114: try output(13)
            case 116: try output(9)
            default: throw DesktopStreamError.malformed
            }
            return false
        }
        if byte == 92 { escaping = true; return false }
        guard highSurrogate == nil else { throw DesktopStreamError.malformed }
        if byte == 34 {
            switch kind {
            case .discard: value = nil
            case .presence: value = .string("")
            case .reply: value = .string(try reply?.finish() ?? "")
            case .key, .scalar, .candidate:
                if let text = try reply?.finish() { value = .string(text) }
                else if overflow { value = .null }
                else {
                    guard let text = String(bytes: bytes, encoding: .utf8) else { throw DesktopStreamError.malformed }
                    value = .string(text)
                }
            }
            return true
        }
        guard byte >= 32 else { throw DesktopStreamError.malformed }
        try output(byte)
        return false
    }
}

/// An async answer is embedded JSON inside a text field. Match its envelope
/// incrementally and retain only IDs plus string-type markers, never answers.
private final class ReplyTextReader {
    static let prefix = Array("<send_user_message_question_reply>".utf8)
    static let suffix = Array("</send_user_message_question_reply>".utf8)
    var prefixCount = 0
    var rejected = false
    var tail: [UInt8] = []
    var tailOffset = 0
    var parser: MetadataJSONParser?
    func consume(_ byte: UInt8) throws {
        guard !rejected else { return }
        if prefixCount < Self.prefix.count {
            if prefixCount == 0 && MetadataJSONParser.whitespace(byte) { return }
            guard byte == Self.prefix[prefixCount] else { rejected = true; return }
            prefixCount += 1
            if prefixCount == Self.prefix.count { parser = MetadataJSONParser(rule: .replyEnvelope) }
            return
        }
        if parser?.complete == true, orderedTail == Self.suffix {
            if !MetadataJSONParser.whitespace(byte) { rejected = true }
            return
        }
        try push(byte)
    }
    func push(_ byte: UInt8) throws {
        if tail.count < Self.suffix.count { tail.append(byte) }
        else {
            let first = tail[tailOffset]
            tail[tailOffset] = byte
            tailOffset = (tailOffset + 1) % tail.count
            do { try parser?.consume(first) }
            catch { rejected = true; parser = nil; tail.removeAll() }
        }
    }
    var orderedTail: [UInt8] { Array(tail.dropFirst(tailOffset)) + Array(tail.prefix(tailOffset)) }
    func finish() throws -> String? {
        guard !rejected, prefixCount == Self.prefix.count, orderedTail == Self.suffix,
              let parser, let value = try? parser.finish() else { return nil }
        // This small canonical envelope lets the existing metadata projection
        // validate answer shape without a second copy of question/answer text.
        let data = try JSONEncoder().encode(value)
        return String(decoding: Self.prefix, as: UTF8.self) + String(decoding: data, as: UTF8.self) + String(decoding: Self.suffix, as: UTF8.self)
    }
}
