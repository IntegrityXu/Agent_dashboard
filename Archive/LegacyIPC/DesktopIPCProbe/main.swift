import Foundation
import CryptoKit
import Darwin

// Bounded Swift reference observer. Build with DesktopStream.swift and its
// domain dependencies. Only use an explicitly authorized disposable UUID.
// This does not enable production counts or sounds.
enum ProbeFailure: Error { case invalidArguments, unsupportedBuild, unsafePath, io, timeout, disconnected, unsupportedProtocol }

func fingerprint(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined() }
func report(_ name: String, _ fields: [String: Any] = [:]) {
    var object = fields; object["kind"] = name; object["time"] = Date().ISO8601Format()
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
}

/// Watch both the directory (atomic replacement) and file (in-place write).
/// The private JSON is ONLY an invalidation hint; its contents never determine
/// read state, account identity, counts, or alerts.
final class ReadStoreInvalidator {
    let queue: Int32
    let directory: Int32
    let path: String
    var file: Int32 = -1
    var previous: Data?
    init(home: URL) throws {
        path = home.appendingPathComponent(".codex-global-state.json").path
        queue = kqueue()
        directory = Darwin.open(home.path, O_EVTONLY | O_NOFOLLOW)
        guard queue >= 0, directory >= 0 else {
            if queue >= 0 { Darwin.close(queue) }; if directory >= 0 { Darwin.close(directory) }
            throw ProbeFailure.io
        }
        watch(directory); reopenFile()
        previous = try digest()
    }
    deinit { if file >= 0 { Darwin.close(file) }; Darwin.close(directory); Darwin.close(queue) }
    func watch(_ fd: Int32) {
        var event = kevent(ident: UInt(fd), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_CLEAR),
            fflags: UInt32(NOTE_WRITE | NOTE_DELETE | NOTE_RENAME), data: 0, udata: nil)
        _ = kevent(queue, &event, 1, nil, 0, nil)
    }
    func reopenFile() {
        if file >= 0 { Darwin.close(file) }
        file = Darwin.open(path, O_EVTONLY | O_NOFOLLOW)
        if file >= 0 { watch(file) }
    }
    func drain() -> Bool {
        var events = Array<Darwin.kevent>(repeating: Darwin.kevent(), count: 8)
        var noWait = timespec(tv_sec: 0, tv_nsec: 0)
        let count = kevent(queue, nil, 0, &events, Int32(events.count), &noWait)
        if count > 0 { reopenFile(); return true }
        return false
    }
    func changed() throws -> Bool {
        let next = try digest()
        defer { previous = next }
        return previous != next
    }
    func digest() throws -> Data {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ProbeFailure.io }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= 16 * 1024 * 1024 else { throw ProbeFailure.unsafePath }
        let data = try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 16 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["electron-thread-read-state-v1"] as? [String: Any] else { throw ProbeFailure.unsupportedProtocol }
        return Data(SHA256.hash(data: try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])))
    }
}

final class DesktopObserver {
    let fd: Int32
    let id: String
    let deadline: Date
    let invalidator: ReadStoreInvalidator
    var stream: DesktopStream
    var decoder = DesktopFrameDecoder()
    var client = "initializing-client"
    var owner: String?
    var requests: [String: (method: String, deadline: Date)] = [:]
    var refreshAt: Date?
    var snapshotDeadline: Date?
    var nextOwnerCheck = Date().addingTimeInterval(15)

    init(id: String, seconds: Int) throws {
        self.id = id; deadline = Date().addingTimeInterval(Double(seconds))
        stream = DesktopStream(conversationID: id, hostID: "local")
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let path = home.appendingPathComponent("ipc/ipc.sock").path
        for (item, type) in [(home.appendingPathComponent("ipc").path, S_IFDIR), (path, S_IFSOCK)] {
            var info = stat()
            guard lstat(item, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == type,
                  info.st_mode & 0o077 == 0 else { throw ProbeFailure.unsafePath }
        }
        invalidator = try ReadStoreInvalidator(home: home)
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw ProbeFailure.io }
        fd = socketFD
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var sendTimeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ProbeFailure.unsafePath }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw ProbeFailure.io }
    }
    deinit { Darwin.close(fd) }
    func send(_ message: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: message)
        var length = UInt32(body.count).littleEndian
        var bytes = withUnsafeBytes(of: &length) { Data($0) }; bytes.append(body)
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { throw ProbeFailure.io }; offset += sent
            }
        }
    }
    func request(_ method: String) throws {
        guard ["initialize", "thread-owner-discovery"].contains(method) else { throw ProbeFailure.unsupportedProtocol }
        let requestID = UUID().uuidString
        requests[requestID] = (method, Date().addingTimeInterval(5))
        let params: [String: Any] = method == "initialize" ? ["clientType": "status-board-observer"] : ["hostId": "local", "conversationId": id]
        try send(["type": "request", "requestId": requestID, "sourceClientId": client,
            "method": method, "version": method == "initialize" ? 0 : 1, "params": params, "timeoutMs": 3000])
    }
    func follow(_ value: Bool) throws {
        try send(["type": "broadcast", "sourceClientId": client, "method": "thread-stream-following-changed", "version": 1,
            "params": ["hostId": "local", "conversationId": id, "following": value]])
        if value { snapshotDeadline = Date().addingTimeInterval(5) }
    }
    func run() throws {
        defer {
            if client != "initializing-client" { try? follow(false) }
            stream.invalidate(); report("closed")
        }
        try request("initialize")
        while Date() < deadline {
            guard !requests.values.contains(where: { Date() > $0.deadline }) else { throw ProbeFailure.timeout }
            if let due = snapshotDeadline, Date() > due { throw ProbeFailure.timeout }
            if owner != nil, Date() >= nextOwnerCheck {
                nextOwnerCheck = Date().addingTimeInterval(15)
                try request("thread-owner-discovery")
            }
            var descriptors = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                               pollfd(fd: invalidator.queue, events: Int16(POLLIN), revents: 0)]
            let ready = poll(&descriptors, 2, 200)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw ProbeFailure.io }
            if descriptors[0].revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { throw ProbeFailure.disconnected }
            if descriptors[1].revents & Int16(POLLIN) != 0, invalidator.drain() {
                // A fixed short delay coalesces writes without postponing forever.
                if refreshAt == nil { refreshAt = Date().addingTimeInterval(0.25) }
            }
            if let due = refreshAt, Date() >= due {
                refreshAt = nil
                if try invalidator.changed(), owner != nil { report("readStoreInvalidation"); try follow(true) }
            }
            if descriptors[0].revents & Int16(POLLIN) != 0 {
                var bytes = [UInt8](repeating: 0, count: 65536)
                let count = recv(fd, &bytes, bytes.count, 0)
                guard count > 0 else { throw ProbeFailure.disconnected }
                for frame in try decoder.append(Data(bytes.prefix(count))) {
                    // Raw content lives only in this frame; the reducer retains an allowlist.
                    try handle(JSONDecoder().decode(WireValue.self, from: frame))
                }
            }
        }
    }
    func handle(_ message: WireValue) throws {
        switch message["type"].string {
        case "client-discovery-request":
            if let requestID = message["requestId"].string {
                try send(["type": "client-discovery-response", "requestId": requestID, "response": ["canHandle": false]])
            }
        case "response":
            guard let requestID = message["requestId"].string, let pending = requests.removeValue(forKey: requestID) else { return }
            guard message["resultType"].string == "success" else { throw ProbeFailure.unsupportedProtocol }
            if pending.method == "initialize" {
                guard let assigned = message["result"]["clientId"].string else { throw ProbeFailure.unsupportedProtocol }
                client = assigned; try request("thread-owner-discovery")
            } else {
                guard let assigned = message["handledByClientId"].string else { throw ProbeFailure.unsupportedProtocol }
                if assigned != owner {
                    stream.invalidate(); owner = assigned; try follow(true); report("subscribed")
                }
            }
        case "broadcast":
            if message["method"].string == "ipc-connection-reset" { throw ProbeFailure.disconnected }
            let params = message["params"]
            guard params["conversationId"].string == id, params["hostId"].string == "local" else { return }
            guard message["method"].string == "thread-stream-state-changed" else { return }
            guard message["version"].integer == 11 else { throw ProbeFailure.unsupportedProtocol }
            guard let sender = message["sourceClientId"].string, sender == owner else {
                stream.invalidate(); owner = nil; try request("thread-owner-discovery"); return
            }
            let events: [DesktopTransition]
            do { events = try stream.accept(change: params["change"], owner: sender) }
            catch {
                report("continuityLost"); stream.invalidate(); try follow(true); return
            }
            if params["change"]["type"].string == "snapshot" { snapshotDeadline = nil }
            if let observed = stream.observation {
                report("observation", ["revision": stream.revision ?? -1,
                    "frameType": params["change"]["type"].string ?? "unknown",
                    "run": fingerprint(observed.runID ?? ""), "status": observed.status ?? "unknown",
                    "unread": observed.unread.map { $0 ? "true" : "false" } ?? "unknown",
                    "pending": observed.pendingRequestIDs.count, "unknownRequests": observed.hasUnclassifiedRequests,
                    "agents": observed.agents.map { ["name": $0.name, "state": $0.state.rawValue] },
                    "transitions": events.map { $0.kind.rawValue }])
            } else { report("projectionUnavailable") }
        default: break
        }
    }
}

do {
    let args = CommandLine.arguments
    guard args.count == 3, UUID(uuidString: args[1]) != nil, let seconds = Int(args[2]), (1...300).contains(seconds) else { throw ProbeFailure.invalidArguments }
    let info = try Data(contentsOf: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
    guard plist?["CFBundleVersion"] as? String == "21477" else { throw ProbeFailure.unsupportedBuild }
    try DesktopObserver(id: args[1], seconds: seconds).run()
} catch {
    let reason = (error as? ProbeFailure).map { String(describing: $0) }
        ?? (error as? DesktopStreamError).map { String(describing: $0) } ?? "invalidInputOrReadFailure"
    report("failed", ["reason": reason]); exit(1)
}
