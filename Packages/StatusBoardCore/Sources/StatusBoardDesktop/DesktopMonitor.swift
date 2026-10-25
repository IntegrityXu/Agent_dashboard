import Foundation
import Darwin
import StatusBoardCore

/// The lock protects control flags only. All protocol and account state belongs
/// to one worker queue; neither callbacks nor UI code can access that state.
public final class DesktopMonitor: @unchecked Sendable {
    private let log = DiagnosticLog.standard
    private let lock = NSLock()
    private var stopped = false
    private var refreshRequested = false
    private var restartRequested = false
    private var suspended = false
    private let queue = DispatchQueue(label: "local.statusboard.observer", qos: .utility)
    private let applicationURL: URL
    private let home: URL
    private let publish: @Sendable (LiveSnapshot) -> Void
    public init(applicationURL: URL, home: URL? = nil, publish: @escaping @Sendable (LiveSnapshot) -> Void) {
        self.applicationURL = applicationURL
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.publish = publish
    }
    public func start() { queue.async { self.run() } }
    public func refresh() { lock.withLock { refreshRequested = true } }
    public func setSuspended(_ value: Bool) {
        lock.withLock { suspended = value; restartRequested = true }
    }
    public func stop(completion: @escaping @Sendable () -> Void) {
        lock.withLock { stopped = true }
        queue.async { completion() }
    }
    private var cancelled: Bool { lock.withLock { stopped } }
    private var sessionCancelled: Bool { lock.withLock { stopped || restartRequested || suspended } }
    private func takeRefresh() -> Bool { lock.withLock { let result = refreshRequested; refreshRequested = false; return result } }
    private func run() {
        // A closed owned helper pipe must become an error, not terminate the UI.
        signal(SIGPIPE, SIG_IGN)
        log.record(.lifecycle, event: "monitor_started", sqliteVersion: ReadOnlyStore.sqliteVersion)
        defer { log.record(.lifecycle, event: "monitor_stopped") }
        var backoff = ReconnectBackoff()
        while !cancelled {
            if lock.withLock({ suspended }) { usleep(100_000); continue }
            lock.withLock { restartRequested = false }
            var rpc: ReadOnlyRPC?
            var session: DesktopSession?
            var stage: DiagnosticStage = .compatibility
            do {
                let build = DesktopCompatibility.build(applicationURL: applicationURL)
                stage = .helper
                let helper = try ReadOnlyRPC(executable: applicationURL.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex").path, cancelled: { self.sessionCancelled })
                rpc = helper
                stage = .initialize
                _ = try helper.request("initialize", ["clientInfo": ["name": "status_board", "version": "0.2.1"], "capabilities": ["experimentalApi": true]])
                try helper.send(["method": "initialized"])
                stage = .identity
                let identity = try VerifiedIdentity.read(helper)
                stage = .socket
                let connectedSession = try DesktopSession(home: home, rpc: helper, identity: identity,
                    cancelled: { self.sessionCancelled }, refresh: { self.takeRefresh() }, publish: publish, log: log, codexBuild: build)
                session = connectedSession
                try connectedSession.run()
            } catch {
                if !sessionCancelled { log.record(session?.failureStage ?? stage, event: "session_reconnect", error: error) }
                let cause = (error as? StageFailure)?.cause ?? error
                var snapshot = LiveSnapshot.failure(cause)
                // Revalidate before showing a cached quota after a source failure.
                // Failed identity verification hides all previous-account data.
                if let rpc, !sessionCancelled, let identity = try? VerifiedIdentity.read(rpc) {
                    snapshot.accountFingerprint = identity.fingerprint
                }
                if !sessionCancelled { publish(snapshot) }
            }
            rpc?.close()
            let delay = backoff.nextDelay(afterHealthySession: session?.isHealthy == true)
            session = nil // Close the failed session's socket before retrying.
            let until = ProcessInfo.processInfo.systemUptime + delay
            while !sessionCancelled && ProcessInfo.processInfo.systemUptime < until {
                if takeRefresh() { break }; usleep(100_000)
            }
        }
    }
}

