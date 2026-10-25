import AppKit
import SwiftUI
import StatusBoardCore
import StatusBoardDesktop

/// Explicit opt-in listening check. No monitor, UI, preferences or Codex calls.
@MainActor
final class AudioPreviewDelegate: NSObject, NSApplicationDelegate {
    let playback = BundledAlertPlayback()
    var kinds: [AlertKind] = [.completed, .waiting, .failed]
    func applicationDidFinishLaunching(_ notification: Notification) { next() }
    func next() {
        guard !kinds.isEmpty else { print("audio-preview finished"); NSApp.terminate(nil); return }
        let kind = kinds.removeFirst()
        let start = ProcessInfo.processInfo.systemUptime
        let started = playback.play(kind) { [weak self] in
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("audio-preview ended \(kind.rawValue) elapsed=\(String(format: "%.3f", elapsed))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.next() }
        }
        print("audio-preview started \(kind.rawValue) success=\(started)")
        if !started { DispatchQueue.main.async { self.next() } }
    }
    func applicationWillTerminate(_ notification: Notification) { playback.stop() }
}

// Opt-in visual QA renders synthetic cases into separate, offscreen views.
// It never changes the live panel, monitoring state, preferences or login items.
extension BoardDelegate {
    func renderDesignCases(beside path: String) {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("design-cases")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for name in ["mixed", "agents", "agents-overflow", "unread", "waiting", "disconnected", "limited", "incompatible-data", "cold", "menu", "collapsed-details", "compact-waiting", "compact-done", "compact-latest-waiting", "compact-latest-done", "compact-offline"] {
                let sample = BoardModel()
                sample.icon = model.icon; sample.expanded = !name.hasPrefix("compact"); sample.pinned = false
                sample.detailsExpanded = name != "collapsed-details"
                sample.now = Date()
                var snapshot = LiveSnapshot()
                snapshot.accountFingerprint = "visual-fixture-only"; snapshot.isConnected = true
                snapshot.counts = TaskCounts(processing: 3, waiting: 1, done: 2)
                if name.hasPrefix("agents") {
                    snapshot.agents = [
                        ProcessingAgent(rootID: "fixture", threadID: "root", path: "/root", state: .running),
                        ProcessingAgent(rootID: "fixture", threadID: "review", path: "/root/reviewer", state: .running),
                        ProcessingAgent(rootID: "fixture", threadID: "test", path: "/root/tester", state: .done)]
                    if name == "agents-overflow" {
                        snapshot.agents += (0..<6).map { ProcessingAgent(rootID: "fixture", threadID: "extra-\($0)",
                            path: "/root/very_long_agent_name_for_layout_verification_\($0)", state: .running) }
                    }
                }
                if name == "unread" || name == "compact-done" { snapshot.counts = TaskCounts(done: 2) }
                if name == "waiting" || name == "compact-waiting" { snapshot.counts = TaskCounts(waiting: 1) }
                if name == "compact-latest-waiting" { snapshot.compactStatus = .waiting }
                if name == "compact-latest-done" { snapshot.compactStatus = .done }
                snapshot.covered = 6; snapshot.total = 6
                snapshot.quota = [QuotaWindow(key: "short", durationMinutes: 300, usedPercent: 28, resetAt: Date()),
                    QuotaWindow(key: "week", durationMinutes: 10080, usedPercent: 82, resetAt: Date())].compactMap { $0 }
                snapshot.quotaUpdatedAt = Date(); snapshot.lastCompleteSyncAt = Date()
                sample.presentation.receive(snapshot)
                if name == "disconnected" || name == "compact-offline" {
                    snapshot.isConnected = false; snapshot.counts = nil; snapshot.quota = []
                    snapshot.updatedAt = Date().addingTimeInterval(-20)
                    sample.presentation.receive(snapshot)
                }
                if name == "cold" { sample.presentation = DashboardPresentation() }
                if name == "limited" {
                    snapshot.codexBuild = "99999"; snapshot.counts = nil
                    snapshot.features = [.tasks: FeatureStatus(.incompatible, "Unsupported task data · retrying"),
                        .quota: FeatureStatus(.available, "Available")]
                    sample.presentation.receive(snapshot)
                }
                if name == "incompatible-data" {
                    snapshot = LiveSnapshot()
                    snapshot.compatibilityIssue = .incompatibleProtocol
                    snapshot.message = snapshot.compatibilityIssue!.message
                    sample.presentation.receive(snapshot)
                }
                sample.settingsOpen = name == "menu"; sample.muted = name == "menu"
                let size = sample.panelSize
                let host = NSHostingView(rootView: BoardView(model: sample))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    host.layoutSubtreeIfNeeded()
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let output = directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
                    }
                    window.close()
                }
            }
        }
    }
}
