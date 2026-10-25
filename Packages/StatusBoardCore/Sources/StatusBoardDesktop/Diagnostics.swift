import Foundation
import StatusBoardCore

/// Fixed vocabulary only: never serialize Error descriptions, paths, IDs,
/// server responses, tokens or conversation content.
enum DiagnosticStage: String, Codable {
    case lifecycle, compatibility, helper, initialize, account, authentication
    case socket, handshake, identity, inventory, readStore, completions, quota, agents
    case discovery, stream, snapshot
}

struct StageFailure: Error {
    let stage: DiagnosticStage
    let cause: Error
}

final class DiagnosticLog: @unchecked Sendable {
    static let standard = DiagnosticLog(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Status Board/diagnostics.jsonl"))
    let url: URL
    private let limit: Int
    private let lock = NSLock()
    private var last: [String: Date] = [:]
    init(url: URL, limit: Int = 1_048_576) { self.url = url; self.limit = limit }

    static func code(_ error: Error) -> String {
        if let error = error as? StageFailure { return code(error.cause) }
        if let error = error as? DesktopFailure {
            switch error {
            case .unavailable: return "unavailable"
            case .unsupported: return "unsupported_schema"
            case .unsafePath: return "unsafe_path"
            case .timeout: return "timeout"
            case .identityChanged: return "identity_changed"
            }
        }
        if let error = error as? RPCFailure {
            switch error {
            case .timeout: return "rpc_timeout"
            case .closed: return "rpc_closed"
            case .oversize: return "rpc_oversize"
            case .protocolError(let code): return "rpc_error_\(code)"
            }
        }
        if let error = error as? StoreFailure { return "sqlite_\(error.code)" }
        if error is DesktopCompatibilityIssue { return "incompatible_version_or_protocol" }
        if let error = error as? DesktopStreamError {
            switch error {
            case .oversize: return "metadata_oversize"
            default: return "invalid_stream_metadata"
            }
        }
        // Numeric NSError codes are useful without its potentially sensitive
        // domain, description or userInfo.
        return "io_error_\((error as NSError).code)"
    }

    func record(_ stage: DiagnosticStage, event: String, error: Error? = nil,
                attempts: Int? = nil, elapsed: Double? = nil, version: Int? = nil,
                throttled: Bool = false, sqliteVersion: String? = nil) {
        lock.withLock {
            let stage = (error as? StageFailure)?.stage ?? stage
            let code = error.map(Self.code)
            let key = stage.rawValue + event + (code ?? "")
            let now = Date()
            if throttled, let previous = last[key], now.timeIntervalSince(previous) < 60 { return }
            last[key] = now
            var row: [String: Any] = ["time": now.ISO8601Format(), "stage": stage.rawValue, "event": event,
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "test"]
            row["error"] = code; row["attempts"] = attempts; row["elapsedSeconds"] = elapsed.map { Int($0) }
            row["protocolVersion"] = version
            row["sqliteVersion"] = sqliteVersion
            if let store = error as? StoreFailure {
                row["sqliteOperation"] = store.operation.rawValue
                row["systemErrno"] = store.systemErrno
                if let files = store.files {
                    row["storeFiles"] = ["database": files.database, "wal": files.wal, "shm": files.shm]
                }
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10])
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                if size + data.count > limit {
                    let backup = url.appendingPathExtension("1")
                    if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
                    if fm.fileExists(atPath: url.path) { try fm.moveItem(at: url, to: backup) }
                }
                if !fm.fileExists(atPath: url.path) {
                    guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
                }
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.seekToEnd(); try file.write(contentsOf: data)
            } catch { /* Diagnostics must never interrupt monitoring. */ }
        }
    }
}

struct SourceFailures {
    struct Failure { let since: Double; var attempts: Int; var incompatible = false }
    static func incompatible(_ error: Error) -> Bool {
        if let staged = error as? StageFailure { return incompatible(staged.cause) }
        if let store = error as? StoreFailure { return [1, 17, 20, 26].contains(store.code & 0xff) }
        if case RPCFailure.protocolError(let code) = error { return [-32601, -32602].contains(code) }
        return (error as? DesktopFailure) == .unsupported || error is DesktopCompatibilityIssue
    }
    private(set) var failures: [DiagnosticStage: Failure] = [:]
    mutating func failed(_ stage: DiagnosticStage, error: Error, now: Double, log: DiagnosticLog?) {
        var failure = failures[stage] ?? Failure(since: now, attempts: 0)
        failure.attempts += 1; failure.incompatible = Self.incompatible(error); failures[stage] = failure
        log?.record(stage, event: "read_failed_retrying", error: error, attempts: failure.attempts,
                    elapsed: now - failure.since, throttled: failure.attempts > 1)
    }
    mutating func recovered(_ stage: DiagnosticStage, now: Double, log: DiagnosticLog?) {
        if let failure = failures.removeValue(forKey: stage) {
            log?.record(stage, event: "recovered", attempts: failure.attempts, elapsed: now - failure.since)
        }
    }
    func expired(_ stage: DiagnosticStage, now: Double, grace: Double = 30) -> Bool {
        failures[stage].map { now - $0.since >= grace } ?? false
    }
}
