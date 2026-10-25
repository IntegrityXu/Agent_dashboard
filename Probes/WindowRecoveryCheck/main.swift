import AppKit
import SwiftUI
import StatusBoardCore
import StatusBoardDesktop

// Compiled alongside the actual app source, with only its @main removed.
// This executable has its own preferences domain and never starts DesktopMonitor.
@main
@MainActor
struct WindowRecoveryCheck {
    static func main() {
        let app = NSApplication.shared
        let delegate = RecoveryCheckDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class RecoveryCheckDelegate: NSObject, NSApplicationDelegate {
    let board = BoardDelegate()
    let previousApp = NSWorkspace.shared.frontmostApplication
    var cover: NSWindow!
    var assertions = 0
    var verifyingQuit = false
    var interceptedQuit = false

    func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        guard condition() else { print("FAIL: \(description)"); exit(1) }
        assertions += 1
        print("PASS: \(description)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Let launch/activation notifications settle before dispatching menu actions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.start() }
    }

    func start() {
        board.panel = BoardPanel(contentRect: NSRect(x: 100, y: 100, width: 320, height: 224),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        board.panel.title = "Status Board recovery check"
        board.panel.acceptsMouseMovedEvents = true
        board.panel.hidesOnDeactivate = false
        board.panel.isReleasedWhenClosed = false
        board.panel.isFloatingPanel = true
        board.panel.delegate = board
        NSWorkspace.shared.notificationCenter.addObserver(board, selector: #selector(BoardDelegate.applicationActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        board.installMenu()
        board.updatePanel()
        board.panel.orderFrontRegardless()
        cover = NSWindow(contentRect: board.panel.frame, styleMask: [.titled], backing: .buffered, defer: false)
        cover.title = "Recovery check covering window"
        cover.isReleasedWhenClosed = false
        cover.orderFrontRegardless()
        check(board.panel.level == board.desktopLevel, "unpinned starts below ordinary windows")
        check(board.pinMenuItem.title == "Pin Status Board", "unpinned menu action")

        // Exercise the real menu target/action. Default-mode scheduling must
        // wait until menu tracking is over, even if key focus is lost there.
        board.menuWillOpen(board.statusItem.menu!)
        board.statusItem.menu!.performActionForItem(at: 0)
        board.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        check(board.revealPending && !board.model.expanded, "Show waits for menu dismissal")
        board.endInteraction()
        check(board.revealPending, "pending reveal survives outside/menu focus callbacks")
        board.menuDidClose(board.statusItem.menu!)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.afterShow() }
    }

    func afterShow() {
        print("Reveal: raised=\(board.raised), pinned=\(board.model.pinned), active=\(NSApp.isActive), frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")
        check(!board.revealPending && board.model.expanded, "Show expands after menu dismissal")
        check(!board.model.pinned && board.raised, "Show leaves saved pin state off")
        check(board.panel.isVisible && board.panel.level == .floating, "Show raises visible native panel above normal level")
        if let previousApp {
            board.applicationActivated(Notification(name: NSWorkspace.didActivateApplicationNotification,
                userInfo: [NSWorkspace.applicationUserInfoKey: previousApp]))
            check(board.raised, "stale activation notification cannot demote current foreground panel")
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ids = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
        print("Native levels: panel=\(board.panel.level.rawValue), cover=\(cover.level.rawValue)")
        for window in windows where [board.panel.windowNumber, cover.windowNumber].contains(window[kCGWindowNumber as String] as? Int ?? -1) {
            print("WindowServer: id=\(window[kCGWindowNumber as String] ?? "?") layer=\(window[kCGWindowLayer as String] ?? "?")")
        }
        if let panelIndex = ids.firstIndex(of: board.panel.windowNumber), let coverIndex = ids.firstIndex(of: cover.windowNumber) {
            check(panelIndex < coverIndex, "WindowServer places revealed panel before covering window")
        } else { check(false, "both native windows must be in WindowServer list") }

        board.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        check(board.panel.level == .floating && board.raised, "key resignation alone does not bury revealed panel")
        board.updatePanel()
        board.receive(LiveSnapshot())
        check(board.panel.level == .floating && board.raised, "layout/data refresh preserves temporary reveal")
        board.endInteraction()
        check(board.panel.level == board.desktopLevel && !board.raised, "outside interaction returns unpinned panel to desktop")

        board.statusItem.menu!.performActionForItem(at: 1)
        check(board.model.pinned && board.defaults.bool(forKey: "pinned"), "menu pins and persists without touching panel")
        check(board.pinMenuItem.title == "Unpin Status Board", "menu changes to Unpin immediately")
        RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { self.afterPin() } }
    }

    func afterPin() {
        board.endInteraction()
        check(board.panel.level == .floating && board.model.pinned, "pinned survives outside interaction")
        board.statusItem.menu!.performActionForItem(at: 1)
        check(!board.model.pinned && !board.defaults.bool(forKey: "pinned"), "menu unpins and persists")
        check(board.pinMenuItem.title == "Pin Status Board", "menu changes back to Pin immediately")
        RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { self.afterUnpin() } }
    }

    func afterUnpin() {
        check(board.panel.level == .floating && board.raised, "menu Unpin leaves panel temporarily reachable")
        board.endInteraction()
        check(board.panel.level == board.desktopLevel, "unpinned panel lowers on next outside interaction")
        board.togglePin()
        check(board.pinMenuItem.title == "Unpin Status Board", "panel pin button synchronizes menu")
        board.togglePin()
        check(board.pinMenuItem.title == "Pin Status Board", "panel unpin button synchronizes menu")
        board.beginInteraction()
        board.menuWillOpen(board.statusItem.menu!)
        board.endInteraction()
        check(board.raised, "opening status menu preserves temporary reveal")
        board.menuDidClose(board.statusItem.menu!)
        board.endInteraction()
        check(!board.raised, "outside interaction works again after menu closes")
        board.showPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.check(NSApp.isActive && self.board.raised, "explicit Show activates app and restores interaction")
            guard let previousApp = self.previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                self.check(false, "app-switch check requires another running application"); return
            }
            self.check(previousApp.activate(options: []), "restore previously active app")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.check(!self.board.raised && self.board.panel.level == self.board.desktopLevel,
                           "real workspace app activation ends temporary reveal")
                self.checkOverhangingAvatar()
            }
        }
    }

    func clickPanel(at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: board.panel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            NSApp.postEvent(event, atStart: false)
        }
    }

    func checkOverhangingAvatar() {
        board.model.toggleExpanded = { [weak self] in self?.board.toggleExpanded() }
        board.model.toggleDetails = { [weak self] in self?.board.toggleDetails() }
        board.model.expanded = true
        board.panel.contentView = BoardHostingView(rootView: BoardView(model: board.model))
        board.updatePanel(); board.beginInteraction(); NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.check(self.board.panel.frame.size == self.board.model.panelSize, "native window includes transparent avatar overhang")
            // Top 12 pt is above the card's top edge (28 pt), inside the avatar.
            self.clickPanel(at: NSPoint(x: 36, y: self.board.panel.frame.height - 12))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.check(!self.board.model.expanded, "clicking avatar above the card border collapses the panel")
                self.check(self.board.panel.frame.size == NSSize(width: 54, height: 54), "collapse removes transparent expanded gutters")
                self.clickPanel(at: NSPoint(x: 27, y: 27))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.check(self.board.model.expanded, "compact avatar click expands the panel again")
                    self.checkAvatarDragging()
                }
            }
        }
    }

    func postMouse(_ type: NSEvent.EventType, at point: NSPoint) {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: board.panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        NSApp.postEvent(event, atStart: false)
    }

    func dragPanel(at point: NSPoint, delta: NSPoint, hold: Double = 0.1, then completion: @escaping @MainActor @Sendable () -> Void) {
        let origin = board.panel.frame.origin
        postMouse(.leftMouseDown, at: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            self.postMouse(.leftMouseDragged, at: NSPoint(x: point.x + delta.x, y: point.y + delta.y))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.check(abs(self.board.panel.frame.minX - origin.x - delta.x) < 1 &&
                    abs(self.board.panel.frame.minY - origin.y - delta.y) < 1, "drag moves the native window by the pointer displacement")
                // Pointer has the original local position after the window moves.
                self.postMouse(.leftMouseUp, at: point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: completion)
            }
        }
    }

    func checkAvatarDragging() {
        let origin = board.panel.frame.origin
        dragPanel(at: NSPoint(x: 36, y: board.panel.frame.height - 12), delta: NSPoint(x: 20, y: 10), hold: 0.7) {
            self.check(self.board.model.expanded, "long-press avatar drag does not collapse")
            self.dragPanel(at: NSPoint(x: 118, y: self.board.panel.frame.height - 61), delta: NSPoint(x: -12, y: -8)) {
                self.check(self.board.model.expanded, "header drags immediately after avatar without a recovery click")
                self.dragPanel(at: NSPoint(x: 200, y: self.board.panel.frame.height - 108), delta: NSPoint(x: 8, y: 6)) {
                    self.check(self.board.model.expanded, "second drag strip remains usable after consecutive gestures")
                    self.board.toggleExpanded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.dragPanel(at: NSPoint(x: 27, y: 27), delta: NSPoint(x: -16, y: -8), hold: 0.7) {
                            self.check(!self.board.model.expanded, "compact long-press drag does not expand")
                            self.clickPanel(at: NSPoint(x: 27, y: 27))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self.check(self.board.model.expanded, "avatar click still works immediately after dragging")
                                self.board.panel.setFrameOrigin(origin)
                                self.checkDragCancellation()
                            }
                        }
                    }
                }
            }
        }
    }

    func checkDragCancellation() {
        guard let content = board.panel.contentView,
              let avatar = content.hitTest(NSPoint(x: 36, y: board.panel.frame.height - 12)) as? DragArea.DragView else {
            check(false, "expanded avatar has a native drag target above the card"); return
        }
        check(avatar.acceptsFirstMouse(for: nil), "avatar accepts the first press on an inactive panel")
        postMouse(.leftMouseDown, at: NSPoint(x: 36, y: board.panel.frame.height - 12))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            avatar.cancelOperation(nil)
            self.postMouse(.leftMouseUp, at: NSPoint(x: 36, y: self.board.panel.frame.height - 12))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.check(self.board.model.expanded, "cancelled avatar press cannot toggle on mouse-up")
                self.dragPanel(at: NSPoint(x: 118, y: self.board.panel.frame.height - 61), delta: NSPoint(x: 5, y: 5)) {
                    self.check(self.board.model.expanded, "cancellation leaves other drag targets usable")
                    self.checkCountPointers()
                }
            }
        }
    }

    func checkCountPointers() {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let content = board.panel.contentView else { check(false, "hosting view exists"); return }
        content.layoutSubtreeIfNeeded()
        let regions = descendants(content).compactMap { $0 as? PointingHandArea.CursorView }
            .sorted { $0.convert(.zero, to: nil).x < $1.convert(.zero, to: nil).x }
        check(regions.count == 3, "all three count buttons have native hand-cursor regions")
        check(regions.allSatisfy { $0.bounds.height == 54 && $0.bounds.width >= 56 }, "hand cursor covers full count cells, including labels")
        check(regions.allSatisfy { $0.hitTest(.zero) == nil }, "cursor regions do not intercept button clicks")
        let originalPointer = NSEvent.mouseLocation
        var opens = 0
        board.model.openCodex = { opens += 1 }
        board.model.now = Date() // Install the action before the next rendered button.
        func move(to point: NSPoint) {
            let screen = self.board.panel.convertPoint(toScreen: point)
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            let location = CGPoint(x: screen.x, y: height - screen.y)
            CGWarpMouseCursorPosition(location)
            self.postMouse(.mouseMoved, at: point)
        }
        func finish() {
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: originalPointer.x, y: height - originalPointer.y))
            NSCursor.arrow.set()
            self.checkDetailsDisclosure()
        }
        func test(_ index: Int) {
            guard index < regions.count else {
                move(to: NSPoint(x: 16, y: self.board.panel.frame.height - 90))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.check(NSCursor.current == NSCursor.arrow, "leaving count cells restores the arrow cursor")
                    self.check(opens == 3, "native cursor overlay preserves every count button action")
                    finish()
                }
                return
            }
            let region = regions[index]
            let point = region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil)
            move(to: point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.check(NSCursor.current == NSCursor.pointingHand, "count cell \(index + 1) shows a hand under real pointer motion")
                self.clickPanel(at: point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { test(index + 1) }
            }
        }
        test(0)
    }

    func checkDetailsDisclosure() {
        board.model.toggleDetails = { [weak self] in self?.board.toggleDetails() }
        let top = board.panel.frame.maxY
        let fullSize = board.panel.frame.size
        clickPanel(at: NSPoint(x: 297, y: board.panel.frame.height - 108))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.check(!self.board.model.detailsExpanded, "chevron click hides details")
            self.check(self.board.panel.frame.size == NSSize(width: 328, height: 168), "details collapse shrinks native window")
            self.check(abs(self.board.panel.frame.maxY - top) < 1, "details collapse preserves top edge")
            self.check(self.board.defaults.object(forKey: "detailsExpanded") as? Bool == false, "details preference is saved")
            self.board.toggleExpanded()
            self.board.toggleExpanded()
            self.check(!self.board.model.detailsExpanded && self.board.panel.frame.height == 168, "avatar round trip preserves folded details")
            self.clickPanel(at: NSPoint(x: 297, y: self.board.panel.frame.height - 108))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.check(self.board.model.detailsExpanded && self.board.panel.frame.size == fullSize, "chevron click restores full details and size")
                self.board.toggleDetails(animated: false)
                self.board.toggleSettings()
                self.check(self.board.model.detailsExpanded && self.board.model.settingsOpen, "settings from folded view expands to fit its menu")
                self.board.toggleDetails(animated: false)
                self.check(!self.board.model.settingsOpen && !self.board.model.detailsExpanded, "folding dismisses settings")
                self.board.toggleDetails(animated: false)
                self.checkDetailsAnimation()
            }
        }
    }

    func checkDetailsAnimation() {
        let fullHeight = board.panel.frame.height
        let top = board.panel.frame.maxY
        board.toggleDetails()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(board.detailsAnimationTimer == nil && board.panel.frame.height == 168, "Reduce Motion applies final layout immediately")
            board.toggleDetails(animated: false)
            checkAgentRows()
            return
        }
        check(board.panel.frame.height == fullHeight, "animation starts from current window height")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            let middle = self.board.panel.frame.height
            self.check(middle > 168 && middle < fullHeight, "native height passes through intermediate frames")
            self.check(abs(self.board.panel.frame.maxY - top) < 1, "animation keeps top edge anchored")
            self.check(abs(self.board.panel.frame.height - self.board.model.panelSize.height) < 1, "native window and content use the same progress")
            if let view = self.board.panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("details-mid-animation.png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
            self.board.toggleDetails()
            self.check(self.board.panel.frame.height == middle, "rapid reversal starts without a frame jump")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.check(self.board.panel.frame.height == fullHeight && self.board.model.detailsExpanded, "rapid reversal reaches expanded layout")
                self.check(self.board.detailsAnimationTimer == nil && self.board.model.animatedDetailsProgress == nil, "animation releases timer and transient progress")
                self.board.toggleDetails(animated: false)
                self.check(self.board.panel.frame.height == 168 && self.board.detailsAnimationTimer == nil, "nonanimated path applies final layout directly")
                self.board.toggleDetails(animated: false)
                self.checkAgentRows()
            }
        }
    }

    func checkAgentRows() {
        var snapshot = LiveSnapshot()
        snapshot.isConnected = true; snapshot.accountFingerprint = "agent-layout-fixture"
        snapshot.counts = TaskCounts(processing: 1)
        snapshot.agents = [ProcessingAgent(rootID: "R", threadID: "R", path: "/root", state: .running),
            ProcessingAgent(rootID: "R", threadID: "A", path: "/root/reviewer", state: .running),
            ProcessingAgent(rootID: "R", threadID: "B", path: "/root/tester", state: .done)]
        let originalHeight = board.model.cardHeight
        board.receive(snapshot)
        check(board.model.agents.map(\.label) == ["root.....", "reviewer.....", "tester done"], "agent rows use name plus running dots or done")
        check(board.model.cardHeight == originalHeight + 81, "agent divider and three rows increase card height")
        check(board.panel.frame.size == board.model.panelSize, "native window grows with agent rows")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("agents-panel.png")
            self.board.renderPreview(output.path)
            snapshot.agents += (0..<8).map { ProcessingAgent(rootID: "R", threadID: "extra-\($0)", path: "/root/extra_\($0)", state: .running) }
            self.board.receive(snapshot)
            self.check(self.board.model.agentsHeight == 121, "agent viewport is capped at five scrollable rows")
            self.board.toggleDetails(animated: false)
            self.check(self.board.panel.frame.height == 168, "folded details hide agent divider and rows")
            self.board.toggleDetails(animated: false)
            self.check(self.board.panel.frame.size == self.board.model.panelSize, "expanding details restores the agent list height")
            snapshot.counts = TaskCounts(done: 1); snapshot.agents = []
            self.board.receive(snapshot)
            self.check(self.board.model.agents.isEmpty && self.board.model.agentsHeight == 0, "task completion removes agent rows and divider")
            self.check(self.board.model.cardHeight == originalHeight, "completion restores original card height")
            self.check(self.board.panel.frame.size == self.board.model.panelSize, "completion shrinks native window")
            self.checkCompactStatus()
        }
    }

    func checkCompactStatus() {
        let sample = BoardModel()
        var snapshot = LiveSnapshot()
        snapshot.isConnected = true; snapshot.accountFingerprint = "compact-fixture"
        snapshot.counts = TaskCounts(waiting: 1, done: 2)
        snapshot.compactStatus = .waiting
        sample.presentation.receive(snapshot)
        check(sample.compactStatus == .waiting, "compact avatar selects waiting when waiting is newest")
        check(sample.compactAccessibilityLabel.contains("Latest status: Waiting"), "waiting badge has contextual accessibility text")
        snapshot.compactStatus = .done; sample.presentation.receive(snapshot)
        check(sample.compactStatus == .done, "newer done replaces waiting with both counts unchanged")
        check(sample.compactAccessibilityLabel.contains("Latest status: Done"), "done badge has contextual accessibility text")
        snapshot.compactStatus = .waiting; sample.presentation.receive(snapshot)
        check(sample.compactStatus == .waiting, "newer waiting replaces done")
        snapshot.counts = TaskCounts(done: 1); snapshot.compactStatus = .done
        sample.presentation.receive(snapshot)
        check(sample.compactStatus == .done, "done-only state displays compact badge")
        snapshot.counts = TaskCounts(); snapshot.compactStatus = nil
        sample.presentation.receive(snapshot)
        check(sample.compactStatus == nil, "clearing waiting and unread done removes compact badge")
        snapshot.counts = TaskCounts(done: 1); snapshot.compactStatus = .done
        sample.presentation.receive(snapshot); sample.now = snapshot.updatedAt.addingTimeInterval(11)
        check(sample.compactStatus == nil, "expired data cannot keep a compact badge")
        checkInfoAndHelp()
    }

    func checkInfoAndHelp() {
        var incompatible = LiveSnapshot()
        incompatible.compatibilityIssue = .incompatibleProtocol
        incompatible.message = incompatible.compatibilityIssue!.message
        board.model.presentation.receive(incompatible); board.model.now = incompatible.updatedAt
        check(board.model.connectionLabel == "Incompatible Codex data", "footer identifies incompatible protocol")
        check(board.model.compactAccessibilityLabel.contains("Incompatible Codex data"), "compact accessibility identifies protocol failure")
        check(board.model.counts == nil && !board.model.connected, "protocol failure never presents live counts")
        var limited = LiveSnapshot()
        limited.isConnected = true; limited.accountFingerprint = "limited-fixture"
        limited.codexBuild = "99999"
        limited.quota = [QuotaWindow(key: "week", durationMinutes: 10080, usedPercent: 40, resetAt: nil)!]
        limited.quotaUpdatedAt = Date()
        limited.features = [.tasks: FeatureStatus(.incompatible, "Unsupported task data · retrying"),
            .quota: FeatureStatus(.available, "Available"),
            .history: FeatureStatus(.unavailable, "Temporarily unavailable · retrying"),
            .agents: FeatureStatus(.unavailable, "Waiting for live tasks")]
        board.model.presentation.receive(limited); board.model.now = limited.updatedAt
        check(board.model.connectionLabel == "Connected · Limited", "partial failure has a distinct connection label")
        check(board.model.counts == nil && board.model.windows.first?.remaining == 60, "unavailable tasks preserve verified quota")
        check(board.model.infoText.contains("Live tasks: Unsupported") && board.model.infoText.contains("Usage: Available"), "Info explains each feature independently")
        check(board.model.infoText.contains("99999"), "new Codex build is diagnostic only")
        check(board.model.compactAccessibilityLabel.contains("Unsupported task data"), "partial failure has accessible task details")
        func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: board.panel.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            _ = board.handleSettingsEvent(event)
        }
        board.model.settingsOpen = true
        board.model.menuSelection = BoardSetting.launchAtLogin.rawValue
        key(125)
        check(board.model.menuSelection == BoardSetting.info.rawValue, "Down reaches the new Info menu item")
        key(119)
        check(board.model.menuSelection == BoardSetting.quit.rawValue, "End selects Quit after Info")
        key(125)
        check(board.model.menuSelection == 0, "four-item menu wraps forward")
        key(48, modifiers: .shift)
        check(board.model.menuSelection == BoardSetting.quit.rawValue, "four-item menu wraps backward")
        board.model.menuSelection = BoardSetting.info.rawValue
        key(36)
        check(board.infoPending && !board.model.settingsOpen, "Return on Info closes settings and schedules its sheet")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let alert = self.board.infoAlert else { self.check(false, "Info sheet opens"); return }
            self.check(self.board.panel.attachedSheet === alert.window, "Info uses a native sheet")
            self.check(alert.informativeText == self.board.model.infoText, "Info includes the current synchronization details")
            self.check(alert.informativeText.contains("99999") && alert.informativeText.contains("Unsupported task data")
                && alert.informativeText.contains("Usage: Available"), "Info explains build and feature-specific recovery")
            self.check(alert.informativeText.contains("Confirmed live conversations:") && alert.informativeText.contains("legacy conversations"), "Info preserves coverage and account-scope explanations")
            self.board.showInfo(); self.board.quit()
            self.check(self.board.infoAlert === alert && self.board.quitAlert == nil, "Info and Quit cannot stack sheets")
            self.board.endInteraction()
            self.check(self.board.raised, "Info keeps the unpinned panel reachable")
            if let view = alert.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("info-dialog.png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
            self.board.panel.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.check(self.board.infoAlert == nil, "OK dismisses Info")
                let menu = self.board.statusItem.menu!
                let index = menu.indexOfItem(withTitle: "Info")
                self.check(index >= 0, "menu-bar icon includes Info")
                self.board.model.expanded = false; self.board.updatePanel()
                menu.performActionForItem(at: index)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard let reopened = self.board.infoAlert else { self.check(false, "menu-bar Info opens"); return }
                    self.check(self.board.model.expanded, "menu-bar Info reveals the compact panel before opening")
                    self.board.panel.endSheet(reopened.window, returnCode: .alertFirstButtonReturn)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.checkQuickHelp() }
                }
            }
        }
    }

    func checkQuickHelp() {
        let help = QuickHelpController()
        let first = UUID(), second = UUID()
        help.schedule("Cancelled hint", owner: first)
        check(!help.isVisible, "help does not appear immediately")
        help.cancel(owner: first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.check(!help.isVisible, "leaving before the delay cancels help")
            let keyWindow = NSApp.keyWindow
            help.schedule("Old hint", owner: first)
            help.schedule("Current hint", owner: second)
            help.cancel(owner: first)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.check(help.isVisible, "help appears within half a second and ignores a stale owner's exit")
                self.check(NSApp.keyWindow === keyWindow, "help never steals keyboard focus")
                help.cancel(owner: second)
                self.check(!help.isVisible, "current owner's exit dismisses help immediately")
                help.schedule("Pending hint", owner: first)
                help.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.check(!help.isVisible, "global dismissal cancels pending help")
                    self.checkQuitConfirmation()
                }
            }
        }
    }

    func checkQuitConfirmation() {
        board.quit()
        guard let alert = board.quitAlert else { check(false, "Quit opens confirmation"); return }
        check(board.panel.attachedSheet === alert.window, "Quit presents a sheet attached to the panel")
        check(alert.buttons[0].title == "Cancel" && alert.buttons[0].keyEquivalent == "\r", "Cancel is the default confirmation action")
        check(alert.buttons[1].title == "Quit" && alert.buttons[1].hasDestructiveAction, "Quit is explicitly marked destructive")
        board.quit()
        check(board.quitAlert === alert, "repeated Quit does not stack dialogs")
        board.endInteraction()
        check(board.raised, "open confirmation keeps an unpinned panel reachable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let view = alert.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("quit-confirmation.png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
            self.board.panel.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.check(self.board.quitAlert == nil && self.board.panel.isVisible, "Cancel closes confirmation and keeps the board running")
                self.verifyingQuit = true
                self.board.quit()
                guard let confirm = self.board.quitAlert else { self.check(false, "confirmation can reopen after Cancel"); return }
                self.board.panel.endSheet(confirm.window, returnCode: .alertSecondButtonReturn)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.check(self.interceptedQuit, "confirmed Quit requests application termination")
                    self.verifyingQuit = false
                    self.finish()
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if verifyingQuit { interceptedQuit = true; return .terminateCancel }
        return .terminateNow
    }

    func finish() {
        print("Window recovery: \(assertions) assertions passed. No Codex monitoring or production preferences used.")
        NSApp.terminate(nil)
    }
}
