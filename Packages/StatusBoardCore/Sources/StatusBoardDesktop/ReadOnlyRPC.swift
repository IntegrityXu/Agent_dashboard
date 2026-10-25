import Foundation
import Darwin

// Read-only protocol discovery. Never print raw responses, credentials, titles,
// thread IDs or content. The helper child is owned exclusively by this monitor.
enum RPCFailure: Error { case timeout, closed, oversize, protocolError(Int) }

protocol DesktopRPC {
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any]
}

final class ReadOnlyRPC: DesktopRPC {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    var buffer = Data()
    var nextID = 1
    let cancelled: () -> Bool

    init(executable: String, cancelled: @escaping () -> Bool) throws {
        self.cancelled = cancelled
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
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
        while ProcessInfo.processInfo.systemUptime < until && !cancelled() {
            if let index = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: index)
                buffer.removeSubrange(...index)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { return object }
                throw RPCFailure.protocolError(-32700)
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno != EINTR { throw RPCFailure.closed }
            if ready > 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                if count <= 0 { throw RPCFailure.closed }
                buffer.append(contentsOf: bytes.prefix(count))
                if buffer.count > 8_000_000 { throw RPCFailure.oversize }
            }
        }
        throw RPCFailure.timeout
    }

    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        let allowed = ["initialize", "account/read", "account/rateLimits/read", "getAuthStatus"]
        precondition(allowed.contains(method))
        let id = nextID
        nextID += 1
        try send(["id": id, "method": method, "params": params])
        let timeout = ProcessInfo.processInfo.systemUptime + 5
        while true {
            let message = try readLine(until: timeout)
            guard message["id"] as? Int == id else { continue }
            if let error = message["error"] as? [String: Any] {
                throw RPCFailure.protocolError(error["code"] as? Int ?? -1)
            }
            return message["result"] as? [String: Any] ?? [:]
        }
    }
}
