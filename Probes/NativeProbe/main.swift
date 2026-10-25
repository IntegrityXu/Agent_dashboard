import AppKit
import SwiftUI
import Intents
import ServiceManagement

@MainActor
final class InteractivePanel: NSPanel {
    var onUserMouseDown: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onUserMouseDown?() }
        super.sendEvent(event)
    }
}

@MainActor
final class ProbeStatus: ObservableObject {
    @Published var focus = "Focus: 未知（保持静音）"
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel?
    var pinned = false
    var expanded = false
    var temporarilyRaised = false
    let status = ProbeStatus()
    var timer: Timer?
    var lastSample = ""
    var statusItem: NSStatusItem?
    let desktopLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        report()
        if CommandLine.arguments.contains("--inspect") {
            NSApp.terminate(nil)
            return
        }
        let panel = InteractivePanel(contentRect: NSRect(x: 100, y: 100, width: 54, height: 54),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.onUserMouseDown = { [weak self] in self?.beginUserInteraction() }
        self.panel = panel
        if CommandLine.arguments.contains("--interactive") { pinned = true; expanded = true }
        if CommandLine.arguments.contains("--interactive") { installRecoveryMenu() }
        updatePanel()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        sample()
        if CommandLine.arguments.contains("--smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                let initiallyCollapsed = panel.frame.size == NSSize(width: 54, height: 54)
                pinned = true; expanded = true; updatePanel()
                let expandedPinned = panel.frame.size == NSSize(width: 320, height: 200) && panel.level == .floating
                expanded = false; updatePanel()
                let collapsedPinned = panel.frame.size == NSSize(width: 54, height: 54) && panel.level == .floating
                pinned = false; updatePanel()
                let desktop = panel.level == desktopLevel
                beginUserInteraction()
                let raised = !pinned && panel.level == .normal && !expanded
                endUserInteraction()
                let lowered = panel.level == desktopLevel && !pinned && !expanded
                let passed = initiallyCollapsed && expandedPinned && collapsedPinned && desktop && raised && lowered
                print("nativePanelConstruction=\(passed ? "PASS" : "FAIL")")
                print("Fullscreen, Spaces, dragging and display removal: NOT_RUN")
                fflush(stdout)
                if !passed { exit(1) }
                NSApp.terminate(nil)
            }
        }
    }

    func installRecoveryMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SB 测试"
        let menu = NSMenu()
        let restore = NSMenuItem(title: "恢复置顶显示", action: #selector(restorePanel), keyEquivalent: "")
        restore.target = self; menu.addItem(restore)
        let quit = NSMenuItem(title: "退出测试", action: #selector(quitProbe), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        item.menu = menu; statusItem = item
    }
    @objc func restorePanel() {
        pinned = true; expanded = true; temporarilyRaised = false
        updatePanel(); panel?.orderFrontRegardless()
        sample(reason: "userRestoredPanel")
    }
    @objc func quitProbe() { NSApp.terminate(nil) }
    func beginUserInteraction() {
        guard let panel else { return }
        if !pinned { temporarilyRaised = true; panel.level = .normal }
        panel.makeKeyAndOrderFront(nil)
        sample(reason: "userInteraction")
    }
    func endUserInteraction() {
        temporarilyRaised = false
        if !pinned { panel?.level = desktopLevel }
        sample(reason: "interactionEnded")
    }
    func windowDidResignKey(_ notification: Notification) { endUserInteraction() }
    func togglePin() {
        pinned.toggle()
        // Clicking Unpin should not hide the controls during this interaction.
        temporarilyRaised = !pinned && (panel?.isKeyWindow ?? false)
        updatePanel()
    }

    @objc func spaceChanged() { sample(reason: "activeSpaceChanged") }
    func windowDidMove(_ notification: Notification) { sample(reason: "windowMoved") }
    func windowDidChangeScreen(_ notification: Notification) { sample(reason: "screenChanged") }
    func requestFocus() {
        print("focusAuthorizationRequestedByUser=true"); fflush(stdout)
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.sample(reason: "focusAuthorizationResponse") }
        }
    }
    func sample(reason: String = "changed") {
        let center = INFocusStatusCenter.default
        let auth = center.authorizationStatus.rawValue
        let focused = center.focusStatus.isFocused.map(String.init) ?? "unknown"
        // Public status is a notification preference, not proof that ALL Focus
        // modes are off when sharing is disabled. This probe never enables audio.
        status.focus = "Focus 授权 \(auth) · 状态 \(focused)\n测试期间保持静音"
        let p = panel
        let line = "authorization=\(auth) focused=\(focused) pinned=\(pinned) raised=\(temporarilyRaised) expanded=\(expanded) level=\(p?.level.rawValue ?? 0) activeSpace=\(p?.isOnActiveSpace ?? false) visible=\(p?.occlusionState.contains(.visible) ?? false) key=\(p?.isKeyWindow ?? false) frame=\(p.map { NSStringFromRect($0.frame) } ?? "none")"
        if line != lastSample || reason != "changed" {
            print("\(Date().ISO8601Format()) \(reason) \(line)")
            fflush(stdout); lastSample = line
        }
    }

    func report() {
        let center = INFocusStatusCenter.default
        print("focusAuthorization=\(center.authorizationStatus.rawValue)")
        print("focusValue=\(center.focusStatus.isFocused.map(String.init) ?? "unknown")")
        print("screenCount=\(NSScreen.screens.count)")
        print("desktopLevel=\(CGWindowLevelForKey(.desktopWindow)) floatingLevel=\(NSWindow.Level.floating.rawValue)")
        print("loginStatus=\(SMAppService.mainApp.status.rawValue); registration was NOT changed")
        print("Focus permission was NOT requested; no sound was played")
        fflush(stdout)
    }

    func updatePanel() {
        guard let panel else { return }
        let anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let size = expanded ? NSSize(width: 320, height: 200) : NSSize(width: 54, height: 54)
        var frame = NSRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        let screen = panel.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
        }
        panel.level = pinned ? .floating : temporarilyRaised ? .normal : desktopLevel
        panel.contentView = NSHostingView(rootView: ProbeView(status: status, expanded: expanded, pinned: pinned,
            toggleForm: { [weak self] in self?.expanded.toggle(); self?.updatePanel() },
            togglePin: { [weak self] in self?.togglePin() },
            requestFocus: { [weak self] in self?.requestFocus() }))
        panel.setFrame(frame, display: true)
        sample(reason: "panelUpdated")
    }
}

struct ProbeView: View {
    @ObservedObject var status: ProbeStatus
    let expanded: Bool
    let pinned: Bool
    let toggleForm: () -> Void
    let togglePin: () -> Void
    let requestFocus: () -> Void
    var body: some View {
        Group {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Status Board 测试").font(.headline)
                        Spacer()
                        Button(pinned ? "取消置顶" : "置顶", action: togglePin)
                            .accessibilityLabel(pinned ? "Unpin to desktop" : "Pin above other apps")
                        Button(action: toggleForm) { Image(systemName: "chevron.down") }
                            .accessibilityLabel("Collapse")
                    }
                    Text(pinned ? "置顶 · 应显示在全屏和各桌面" : "桌面层 · 应被普通窗口遮挡").font(.caption)
                    Text(status.focus).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("请求 Focus 授权", action: requestFocus)
                        Spacer()
                        Button("退出测试") { NSApp.terminate(nil) }.keyboardShortcut("q")
                    }
                }.padding(16)
            } else {
                Button(action: toggleForm) { Image(systemName: "rectangle.on.rectangle").font(.title2).frame(width: 54, height: 54) }
                    .buttonStyle(.plain).accessibilityLabel("Expand native window probe")
                    .contextMenu { Button("Quit probe") { NSApp.terminate(nil) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: expanded ? 20 : 16))
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
