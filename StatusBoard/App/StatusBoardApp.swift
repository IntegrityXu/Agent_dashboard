import AppKit
import SwiftUI
import StatusBoardCore
import StatusBoardDesktop

@main
@MainActor
struct StatusBoardApp {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--preview-sounds") {
            let preview = AudioPreviewDelegate()
            app.delegate = preview
            app.setActivationPolicy(.prohibited)
            withExtendedLifetime(preview) { app.run() }
            return
        }
        let delegate = BoardDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class BoardDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = BoardModel()
    let audio = AudioNotifications(playback: BundledAlertPlayback())
    var panel: BoardPanel!
    var statusItem: NSStatusItem!
    var pinMenuItem: NSMenuItem!
    var statusMenuTracking = false
    var revealPending = false
    var quitAlert: NSAlert?
    var infoAlert: NSAlert?
    var infoPending = false
    var monitor: DesktopMonitor?
    var timer: Timer?
    var detailsAnimationTimer: Timer?
    var raised = false
    var terminating = false
    var applicationURL: URL?
    var rendered = false
    var preferredScreen: Int?
    var localEventMonitor: Any?
    var outsideEventMonitor: Any?
    let desktopLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: "local.statusboard.app").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(.init("local.statusboard.show"), object: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showPanel), name: .init("local.statusboard.show"), object: nil)
        applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        if let applicationURL { model.icon = NSWorkspace.shared.icon(forFile: applicationURL.path) }
        preferredScreen = defaults.object(forKey: "screenNumber") as? Int
        model.pinned = defaults.object(forKey: "pinned") as? Bool ?? false
        model.expanded = defaults.object(forKey: "expanded") as? Bool ?? false
        model.detailsExpanded = defaults.object(forKey: "detailsExpanded") as? Bool ?? true
        model.togglePin = { [weak self] in self?.togglePin() }
        model.toggleExpanded = { [weak self] in self?.toggleExpanded() }
        model.toggleDetails = { [weak self] in self?.toggleDetails() }
        model.openCodex = { [weak self] in self?.openCodex() }
        model.requestQuit = { [weak self] in self?.quit() }
        if let data = defaults.data(forKey: "savedUsage"), let saved = try? JSONDecoder().decode(SavedUsage.self, from: data) {
            model.presentation = DashboardPresentation(saved: saved)
        }
        model.muted = defaults.bool(forKey: "muteSounds")
        audio.setMuted(model.muted)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        readLoginStatus()
        model.toggleSettings = { [weak self] in self?.toggleSettings() }
        model.selectSetting = { [weak self] index in self?.selectSetting(index) }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        panel = BoardPanel(contentRect: NSRect(x: visible.maxX - 344, y: visible.maxY - 350, width: 320, height: 310),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Status Board"
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        panel.delegate = self
        panel.onMouseDown = { [weak self] in self?.beginInteraction() }
        panel.contentView = BoardHostingView(rootView: BoardView(model: model))
        if let frame = defaults.string(forKey: "frame") { panel.setFrame(NSRectFromString(frame), display: false) }
        updatePanel(); panel.orderFrontRegardless()
        installMenu()
        installSettingsDismissal()
        if CommandLine.arguments.contains("--preview-settings") { model.settingsOpen = true }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let applicationURL {
            let monitor = DesktopMonitor(applicationURL: applicationURL) { [weak self] snapshot in
                // Serial worker -> main queue preserves event/invalidation order.
                DispatchQueue.main.async { self?.receive(snapshot) }
            }
            self.monitor = monitor; monitor.start()
        } else {
            var snapshot = LiveSnapshot(); snapshot.message = "Codex app not found"
            model.presentation.receive(snapshot)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previousHeight = self.model.cardHeight
                self.model.now = Date()
                if previousHeight != self.model.cardHeight { self.updatePanel() }
                self.audio.checkHealth()
            }
        }
        if let value = argument("--quit-after"), let seconds = Double(value), seconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
        }
    }
    func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    @objc func willSleep() {
        QuickHelpController.shared.dismiss()
        audio.setSuspended(true); monitor?.setSuspended(true)
    }
    @objc func didWake() {
        audio.setSuspended(false); monitor?.setSuspended(false)
    }
    func receive(_ snapshot: LiveSnapshot) {
        guard !terminating else { return }
        audio.receive(snapshot)
        let previousHeight = model.cardHeight
        let previousSaved = model.presentation.saved
        model.presentation.receive(snapshot); model.now = Date()
        if previousSaved != model.presentation.saved, let saved = model.presentation.saved,
           let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "savedUsage") }
        if previousHeight != model.cardHeight { updatePanel() }
        writeSnapshotDiagnostics(snapshot)
        if !rendered, snapshot.covered > 0, let path = argument("--render-preview") {
            rendered = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.renderPreview(path) }
        }
    }
    func renderPreview(_ path: String) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        if CommandLine.arguments.contains("--render-design-cases") { renderDesignCases(beside: path) }
    }
    func installSettingsDismissal() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleSettingsEvent(event) == nil
            }
            return consumed ? nil : event
        }
        outsideEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Mouse monitors run on the main thread. Handle the click now so an
            // old event cannot demote a subsequent menu-triggered reveal.
            MainActor.assumeIsolated { self?.endInteraction() }
        }
    }
    func handleSettingsEvent(_ event: NSEvent) -> NSEvent? {
        guard model.settingsOpen else { return event }
        if event.type == .keyDown {
            let count = BoardSetting.allCases.count
            switch event.keyCode {
            case 53: model.settingsOpen = false; return nil
            case 125, 48:
                let step = event.keyCode == 48 && event.modifierFlags.contains(.shift) ? -1 : 1
                model.menuSelection = ((model.menuSelection ?? (step > 0 ? -1 : count)) + step + count) % count
                return nil
            case 115: model.menuSelection = 0; return nil
            case 119: model.menuSelection = count - 1; return nil
            case 126: model.menuSelection = ((model.menuSelection ?? count) + count - 1) % count; return nil
            case 36, 76, 49: selectSetting(model.menuSelection ?? 0); return nil
            default: return event
            }
        }
        guard event.window === panel else { model.settingsOpen = false; return event }
        let point = CGPoint(x: event.locationInWindow.x, y: panel.frame.height - event.locationInWindow.y)
        if !model.menuFrame.contains(point) && !model.gearFrame.contains(point) { model.settingsOpen = false }
        return event
    }
    func installMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Status Board")
        let menu = NSMenu()
        menu.delegate = self
        for (title, selector) in [("Show Status Board", #selector(showPanel)), ("Pin Status Board", #selector(togglePinFromMenu)), ("Refresh", #selector(refresh)), ("Open Codex", #selector(openCodex)), ("Info", #selector(showInfo)), ("Quit", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
            if selector == #selector(togglePinFromMenu) { pinMenuItem = item }
        }
        statusItem.menu = menu
        updatePinMenu()
    }
    func menuWillOpen(_ menu: NSMenu) { QuickHelpController.shared.dismiss(); statusMenuTracking = true; updatePinMenu() }
    func menuDidClose(_ menu: NSMenu) { statusMenuTracking = false }
    func updatePinMenu() {
        pinMenuItem?.title = model.pinned ? "Unpin Status Board" : "Pin Status Board"
    }
    @objc func togglePinFromMenu() {
        togglePin()
        showPanel()
    }
    @objc func showPanel() {
        guard !revealPending else { return }
        revealPending = true
        // Only run after AppKit exits menu tracking and finishes restoring focus.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.revealPending = false
                guard !self.terminating else { return }
                self.model.expanded = true
                self.defaults.set(true, forKey: "expanded")
                self.raised = !self.model.pinned
                self.updatePanel()
                NSApp.activate(ignoringOtherApps: true)
                self.beginInteraction()
                self.panel.orderFrontRegardless()
            }
        }
    }
    @objc func refresh() { monitor?.refresh() }
    @objc func openCodex() {
        guard let applicationURL else { return }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func showInfo() {
        guard infoAlert == nil, !infoPending, quitAlert == nil else { return }
        QuickHelpController.shared.dismiss()
        model.settingsOpen = false
        infoPending = true
        // Menu-bar actions finish after AppKit leaves its tracking loop.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.infoPending = false
                guard !self.terminating else { return }
                self.model.expanded = true
                self.defaults.set(true, forKey: "expanded")
                self.updatePanel()
                self.beginInteraction()
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Status Board Info"
                alert.informativeText = self.model.infoText
                alert.alertStyle = .informational
                alert.icon = self.model.icon
                alert.addButton(withTitle: "OK")
                self.infoAlert = alert
                alert.beginSheetModal(for: self.panel) { [weak self] _ in
                    self?.infoAlert = nil
                    self?.beginInteraction()
                }
            }
        }
    }
    @objc func quit() {
        guard quitAlert == nil, infoAlert == nil, !infoPending else { return }
        QuickHelpController.shared.dismiss()
        model.settingsOpen = false
        beginInteraction()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quit Status Board?"
        alert.informativeText = "The status board and its notifications will stop."
        alert.alertStyle = .warning
        alert.icon = model.avatar
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[1].hasDestructiveAction = true
        quitAlert = alert
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            self.quitAlert = nil
            if response == .alertSecondButtonReturn { NSApp.terminate(nil) }
            else { self.beginInteraction() }
        }
    }
    @objc func screensChanged() { updatePanel() }
    func beginInteraction() {
        if !model.pinned { raised = true }
        updatePanelLevel()
        panel.makeKeyAndOrderFront(nil)
    }
    func windowDidResignKey(_ notification: Notification) {
        panel.clearHandCursor()
        QuickHelpController.shared.dismiss()
        // Menus can take key focus too. Only an outside click or app switch
        // ends a temporary reveal, not this notification.
        model.settingsOpen = false
    }
    @objc func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        endInteraction()
    }
    func endInteraction() {
        QuickHelpController.shared.dismiss()
        guard !statusMenuTracking, !revealPending, quitAlert == nil, infoAlert == nil, !infoPending else { return }
        model.settingsOpen = false
        raised = false
        updatePanelLevel()
    }
    func updatePanelLevel() {
        panel.level = model.pinned || raised ? .floating : desktopLevel
    }
    func togglePin() {
        model.pinned.toggle()
        // Unpin remains reachable until the user returns to another app.
        raised = !model.pinned
        defaults.set(model.pinned, forKey: "pinned"); updatePanel()
        updatePinMenu()
    }
    func toggleExpanded() {
        QuickHelpController.shared.dismiss()
        model.settingsOpen = false
        model.expanded.toggle(); defaults.set(model.expanded, forKey: "expanded"); updatePanel()
    }
    func toggleDetails(animated: Bool = true) {
        QuickHelpController.shared.dismiss()
        let start = model.detailsProgress
        detailsAnimationTimer?.invalidate()
        detailsAnimationTimer = nil
        model.settingsOpen = false
        model.detailsExpanded.toggle()
        defaults.set(model.detailsExpanded, forKey: "detailsExpanded")
        guard animated && model.expanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            updatePanel()
            return
        }
        let target: CGFloat = model.detailsExpanded ? 1 : 0
        let began = ProcessInfo.processInfo.systemUptime
        model.animatedDetailsProgress = start
        // One clock drives both AppKit bounds and SwiftUI content, including reversals.
        let animationTimer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.26)
                let eased = t * t * (3 - 2 * t)
                self.model.animatedDetailsProgress = start + (target - start) * eased
                if t >= 1 {
                    self.updatePanel()
                } else {
                    self.updatePanel(finishingDetailsAnimation: false)
                }
            }
        }
        detailsAnimationTimer = animationTimer
        RunLoop.main.add(animationTimer, forMode: .common)
    }
    func toggleSettings() {
        QuickHelpController.shared.dismiss()
        readLoginStatus()
        model.menuSelection = nil
        // The inline settings menu needs the expanded card's vertical room.
        if !model.settingsOpen && !model.detailsExpanded {
            model.detailsExpanded = true
            defaults.set(true, forKey: "detailsExpanded")
            updatePanel()
        }
        model.settingsOpen.toggle()
    }
    func windowDidMove(_ notification: Notification) {
        guard detailsAnimationTimer == nil else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: "frame")
        if let number = panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int {
            preferredScreen = number; defaults.set(number, forKey: "screenNumber")
        }
    }
    func updatePanel(finishingDetailsAnimation: Bool = true) {
        if finishingDetailsAnimation {
            detailsAnimationTimer?.invalidate()
            detailsAnimationTimer = nil
            model.animatedDetailsProgress = nil
        }
        let size = model.panelSize
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        let remembered = preferredScreen.flatMap { number in
            NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int) == number }
        }
        let screen = preferredScreen == nil
            ? NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
            : remembered ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
        }
        updatePanelLevel()
        panel.setFrame(frame, display: true)
        if finishingDetailsAnimation { defaults.set(NSStringFromRect(frame), forKey: "frame") }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        QuickHelpController.shared.dismiss()
        detailsAnimationTimer?.invalidate()
        audio.shutdown()
        guard let monitor, !terminating else { return .terminateNow }
        terminating = true; timer?.invalidate()
        monitor.stop {
            // terminateLater runs a nested AppKit loop. A main-queue Task can
            // deadlock when quit originated on that queue; use the run loop.
            RunLoop.main.perform(inModes: [.common, .default, .modalPanel]) {
                MainActor.assumeIsolated { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }
}

