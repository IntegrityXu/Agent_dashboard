import Foundation
import Darwin

// Read-only protocol discovery. Never print raw responses, credentials, titles,
// thread IDs or content. The child is owned exclusively by this probe.
enum ProbeFailure: Error { case timeout, closed, oversize, protocolError(Int) }

final class RPCProbe {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    var buffer = Data()
    var nextID = 1
    let deadline = ProcessInfo.processInfo.systemUptime + 25

    init(executable: String, proxy: Bool) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = proxy ? ["app-server", "proxy"] : ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice // Never retain raw server logs.
        try process.run()
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let end = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning && ProcessInfo.processInfo.systemUptime < end { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }

    func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func readLine(until: Double) throws -> [String: Any] {
        while ProcessInfo.processInfo.systemUptime < min(until, deadline) {
            if let index = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: index)
                buffer.removeSubrange(...index)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { return object }
                throw ProbeFailure.protocolError(-32700)
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno != EINTR { throw ProbeFailure.closed }
            if ready > 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                if count <= 0 { throw ProbeFailure.closed }
                buffer.append(contentsOf: bytes.prefix(count))
                if buffer.count > 8_000_000 { throw ProbeFailure.oversize }
            }
        }
        throw ProbeFailure.timeout
    }

    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        let allowed = ["initialize", "account/read", "account/rateLimits/read", "thread/list", "thread/loaded/list"]
        precondition(allowed.contains(method))
        let id = nextID
        nextID += 1
        try send(["id": id, "method": method, "params": params])
        let timeout = ProcessInfo.processInfo.systemUptime + 5
        while true {
            let message = try readLine(until: timeout)
            guard message["id"] as? Int == id else { continue }
            if let error = message["error"] as? [String: Any] {
                throw ProbeFailure.protocolError(error["code"] as? Int ?? -1)
            }
            return message["result"] as? [String: Any] ?? [:]
        }
    }
}

signal(SIGPIPE, SIG_IGN)
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("Usage: CodexProbe /absolute/path/to/codex [--proxy]")
    exit(64)
}
do {
    let proxy = arguments.contains("--proxy")
    let probe = try RPCProbe(executable: arguments[1], proxy: proxy)
    defer { probe.close() }
    let initial = try probe.request("initialize", ["clientInfo": ["name": "status_board_readonly_probe", "version": "0.1.0"], "capabilities": ["experimentalApi": true]])
    print("transport=\(proxy ? "default-proxy" : "owned-stdio") initialized=true fields=\(initial.keys.sorted())")
    try probe.send(["method": "initialized", "params": [:]])
    for method in ["account/read", "account/rateLimits/read", "thread/loaded/list", "thread/list"] {
        do {
            let params: [String: Any] = method == "account/read" ? ["refreshToken": false] :
                method == "thread/list" ? ["limit": 100, "archived": false, "useStateDbOnly": true, "modelProviders": [], "sourceKinds": ["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"]] : [:]
            let result = try probe.request(method, params)
            print("\(method) success=true fields=\(result.keys.sorted())")
            if method == "account/read" {
                let account = result["account"] as? [String: Any]
                print("accountPresent=\(account != nil) accountFields=\(account?.keys.sorted() ?? [])")
                let routing = result["workspaceRouting"] as? [String: Any]
                print("workspaceAccountIDPresent=\((routing?["chatgptAccountId"] as? String)?.isEmpty == false)")
            }
            if method == "account/rateLimits/read" {
                print("accountIDPresent=\((result["accountId"] as? String)?.isEmpty == false)")
                let buckets = result["rateLimitsByLimitId"] as? [String: Any] ?? [:]
                print("quotaBucketCount=\(buckets.count)")
            }
            if method == "thread/loaded/list" { print("loadedCount=\((result["data"] as? [Any])?.count ?? 0)") }
            if method == "thread/list", let rows = result["data"] as? [[String: Any]] {
                print("pageCount=\(rows.count) hasNextPage=\(result["nextCursor"] is String)")
                print("threadFields=\(Set(rows.flatMap { $0.keys }).sorted())")
                let receipts = result["readStates"] as? [String: Any]
                print("readStatesAvailable=\(receipts != nil) receiptCount=\(receipts?.count ?? 0)")
                let states = rows.compactMap { ($0["status"] as? [String: Any])?["type"] as? String }
                print("runtimeStates=\(Dictionary(grouping: states, by: { $0 }).mapValues { $0.count })")
            }
        } catch { print("\(method) failure=\(error)") }
    }
} catch {
    print("probe failure=\(error)")
    exit(1)
}
