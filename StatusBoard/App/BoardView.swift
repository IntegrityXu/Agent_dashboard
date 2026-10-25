import AppKit
import SwiftUI
import StatusBoardCore
import StatusBoardDesktop

/// One event-driven gesture for both avatar sizes and the panel's drag strips.
/// Never drain AppKit's event queue: mouse-up must finish normal window dispatch.
struct DragArea: NSViewRepresentable {
    var click: (() -> Void)?
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.click = click; return view }
    func updateNSView(_ view: DragView, context: Context) { view.click = click }
    class DragView: NSView {
        var click: (() -> Void)?
        private var start: (pointer: NSPoint, origin: NSPoint)?
        private var didDrag = false
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            cancelPress()
            guard let window else { return }
            QuickHelpController.shared.dismiss()
            start = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let start else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let delta = NSPoint(x: point.x - start.pointer.x, y: point.y - start.pointer.y)
            if hypot(delta.x, delta.y) > 4 { didDrag = true }
            guard didDrag else { return }
            window.setFrameOrigin(NSPoint(x: start.origin.x + delta.x, y: start.origin.y + delta.y))
        }
        override func mouseUp(with event: NSEvent) {
            let shouldClick = start != nil && !didDrag && bounds.contains(convert(event.locationInWindow, from: nil))
            cancelPress() // Clear before a click replaces this view during collapse.
            if shouldClick { click?() }
        }
        override func cancelOperation(_ sender: Any?) { cancelPress() }
        override func viewWillMove(toWindow newWindow: NSWindow?) { cancelPress(); super.viewWillMove(toWindow: newWindow) }
        private func cancelPress() { start = nil; didDrag = false }
    }
}

/// Geometry-only native region. BoardPanel applies the cursor after SwiftUI's
/// event handling; this view never intercepts the button's mouse or keyboard input.
struct PointingHandArea: NSViewRepresentable {
    var enabled: Bool
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.enabled = enabled
        if !enabled { (view.window as? BoardPanel)?.clearHandCursor() }
    }
    class CursorView: NSView {
        var enabled = true
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let panel = window as? BoardPanel {
                panel.handCursorViews.remove(self)
                panel.clearHandCursor()
            }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            (window as? BoardPanel)?.handCursorViews.add(self)
        }
    }
}

/// Own the cursor rectangles at the hosting boundary, after SwiftUI updates its
/// own tracking. Active-always tracking also works on the nonactivating panel.
final class BoardHostingView: NSHostingView<BoardView> {
    private var pointerTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil)
        addTrackingArea(area); pointerTracking = area
        super.updateTrackingAreas()
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let panel = window as? BoardPanel else { return }
        for view in panel.handCursorViews.allObjects where view.enabled && !view.isHiddenOrHasHiddenAncestor {
            addCursorRect(convert(view.visibleRect, from: view), cursor: .pointingHand)
        }
    }
    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        (window as? BoardPanel)?.updateHandCursor(at: event.locationInWindow)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        (window as? BoardPanel)?.updateHandCursor(at: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (window as? BoardPanel)?.updateHandCursor(at: event.locationInWindow)
    }
    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
        (window as? BoardPanel)?.refreshHandCursor()
    }
}

private enum BoardPalette {
    static func green(_ dark: Bool) -> Color { dark ? Color(red: 0.46, green: 0.82, blue: 0.65) : Color(red: 0.15, green: 0.45, blue: 0.30) }
    static func orange(_ dark: Bool) -> Color { dark ? Color(red: 0.94, green: 0.73, blue: 0.49) : Color(red: 0.57, green: 0.32, blue: 0.07) }
    static func red(_ dark: Bool) -> Color { dark ? Color(red: 0.96, green: 0.61, blue: 0.61) : Color(red: 0.67, green: 0.20, blue: 0.20) }
    static func blue(_ dark: Bool) -> Color { dark ? Color(red: 0.62, green: 0.75, blue: 0.95) : Color(red: 0.18, green: 0.35, blue: 0.63) }
}

struct BoardView: View {
    @ObservedObject var model: BoardModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @SwiftUI.FocusState private var settingsFocused: Bool
    private var dark: Bool { scheme == .dark }
    private var mutedText: Color { dark ? Color(white: 0.76) : Color(white: 0.33) }
    var body: some View {
        Group {
            if model.expanded {
                ZStack(alignment: .topLeading) {
                    card
                        .frame(width: 320, height: model.cardHeight)
                        .background { frostedBackground }
                        .overlay { border }
                        .padding(.top, BoardModel.avatarOverhang.height)
                        .padding(.leading, BoardModel.avatarOverhang.width)
                    Image(nsImage: model.avatar).resizable().scaledToFit()
                        .frame(width: 72, height: 72)
                        .overlay { DragArea(click: model.toggleExpanded) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Collapse Status Board")
                        .accessibilityAddTraits(.isButton).accessibilityAction { model.toggleExpanded() }
                        .focusable()
                        .onKeyPress(.space) { model.toggleExpanded(); return .handled }
                        .onKeyPress(.return) { model.toggleExpanded(); return .handled }
                }
                .frame(width: model.panelSize.width, height: model.panelSize.height)
            }
            else {
                Image(nsImage: model.avatar).resizable().scaledToFit().frame(width: 44, height: 44).opacity(model.connected ? 1 : 0.65)
                    .frame(width: 54, height: 54)
                    .background { frostedBackground }
                    .overlay { border }
                    .overlay(alignment: .topTrailing) {
                        if let status = model.compactStatus {
                            Text(status == .waiting ? "!" : "✓").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(dark ? Color.black : Color.white)
                                .frame(width: 19, height: 19)
                                .background(status == .waiting ? BoardPalette.orange(dark) : BoardPalette.green(dark), in: Circle())
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay { DragArea(click: model.toggleExpanded) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.compactAccessibilityLabel)
                    .accessibilityAddTraits(.isButton).accessibilityAction { model.toggleExpanded() }
                    .focusable()
                    .onKeyPress(.space) { model.toggleExpanded(); return .handled }
                    .onKeyPress(.return) { model.toggleExpanded(); return .handled }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if model.expanded && model.settingsOpen {
                settingsMenu.padding(.top, 54 + BoardModel.avatarOverhang.height).padding(.trailing, 16)
            }
        }
        .saturation(model.connected ? 1 : 0)
        .coordinateSpace(name: "board")
        .onChange(of: model.settingsOpen) { _, open in if !open { settingsFocused = true } }
    }
    private var frostedBackground: some View {
        // Fade only the material, keeping foreground text and controls opaque.
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .opacity(dark && !reduceTransparency ? 0.76 : 1)
            .allowsHitTesting(false)
    }
    private var border: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(.white.opacity(dark ? 0.16 : 0.55), lineWidth: 1)
            .allowsHitTesting(false)
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 34, height: 34).allowsHitTesting(false).accessibilityHidden(true)
                DragArea().frame(maxWidth: .infinity).frame(height: 34).quickHelp("Drag to move")
                Button(action: model.toggleSettings) { controlIcon("gearshape", active: model.settingsOpen) }
                    .buttonStyle(BoardControlStyle())
                    .focusable().focused($settingsFocused).focusEffectDisabled()
                    .quickHelp("Settings").accessibilityLabel("Settings")
                    .accessibilityValue(model.settingsOpen ? "Expanded" : "Collapsed")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { model.gearFrame = $0 }
                Button(action: model.togglePin) {
                    controlIcon("pin", active: model.pinned).foregroundStyle(model.pinned && model.connected ? BoardPalette.blue(dark) : .primary)
                }.buttonStyle(BoardControlStyle())
                    .quickHelp(model.pinned ? "Unpin to desktop" : "Pin above other apps")
                    .accessibilityLabel(model.pinned ? "Unpin to desktop" : "Pin above other apps")
                Button(action: model.requestQuit) { controlIcon("power") }
                    .buttonStyle(BoardControlStyle()).quickHelp("Quit Status Board…")
                    .accessibilityLabel("Quit Status Board")
            }.frame(height: 34).padding(.bottom, 7)
            Divider().frame(height: 1).padding(.bottom, 6)
            HStack(spacing: 10) {
                Image(nsImage: model.icon).resizable().frame(width: 28, height: 28)
                    .opacity(model.connected ? 1 : 0.65).accessibilityHidden(true)
                Text("Codex").font(.system(size: 14, weight: .medium))
                DragArea().frame(maxWidth: .infinity).frame(height: 30).quickHelp("Drag to move")
                Button(action: model.toggleDetails) {
                    controlIcon("chevron.down").rotationEffect(.degrees(180 * model.detailsProgress))
                }.buttonStyle(BoardControlStyle())
                    .quickHelp(model.detailsExpanded ? "Hide details" : "Show details")
                    .accessibilityLabel(model.detailsExpanded ? "Hide details" : "Show details")
                    .accessibilityValue(model.detailsExpanded ? "Expanded" : "Collapsed")
            }.frame(height: 30)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    if model.windows.isEmpty {
                        VStack(spacing: 7) {
                            HStack {
                                Text("Usage remaining").font(.system(size: 12)).foregroundStyle(mutedText)
                                Spacer(); Text("—").font(.system(size: 14, weight: .medium))
                            }
                            Capsule().fill(.primary.opacity(0.08)).frame(height: 4)
                        }.frame(height: 29)
                    } else { ForEach(model.windows, id: \.key) { quotaRow($0) } }
                }.padding(.bottom, 18)
                Divider()
                HStack(spacing: 4) {
                    count(model.counts?.processing, label: "processing", tint: BoardPalette.blue(dark)).frame(width: 77)
                    count(model.counts?.waiting, label: "Waiting for operation", tint: BoardPalette.orange(dark)).frame(width: 147)
                    count(model.counts?.done, label: "Done", tint: BoardPalette.green(dark), unread: (model.counts?.done ?? 0) > 0).frame(width: 56)
                }.frame(height: 54).padding(.top, 12)
                if !model.agents.isEmpty {
                    Divider().padding(.top, 10).padding(.bottom, 10)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.agents) { agent in
                                HStack(spacing: 0) {
                                    Text(agent.name).lineLimit(1).truncationMode(.middle)
                                    Text(agent.state.suffix).fixedSize()
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 12)).foregroundStyle(mutedText)
                                .frame(height: 20)
                                .quickHelp(agent.path + agent.state.suffix)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(agent.name)
                                .accessibilityValue(agent.state == .running ? "Running" : agent.state.rawValue)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: CGFloat(min(5, model.agents.count)) * 20)
                }
            }
            .padding(.top, 20 * 2.0 / 3.0)
            .frame(height: model.detailsHeight, alignment: .top)
            .frame(height: model.detailsHeight * model.detailsProgress, alignment: .top)
            .clipped()
            .opacity(model.detailsProgress)
            .allowsHitTesting(model.detailsExpanded && model.animatedDetailsProgress == nil)
            .disabled(!model.detailsExpanded)
            .accessibilityHidden(!model.detailsExpanded)
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(model.connected ? BoardPalette.green(dark) : Color.secondary).frame(width: 5, height: 5)
                    Text(model.connectionLabel).lineLimit(1).minimumScaleFactor(0.85)
                }
                .quickHelp(model.presentation.latest.compatibilityIssue?.message
                    ?? TimeLabel.text(prefix: "Last updated", date: model.presentation.lastCompleteSyncAt))
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Text(model.pinned ? "Pinned" : "Desktop")
            }.font(.system(size: 11)).foregroundStyle(mutedText).padding(.top, 16.5)
        }.padding(16)
    }
    private func controlIcon(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .regular)).frame(width: 30, height: 30)
            .background(active ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }
    private var settingsMenu: some View {
        VStack(spacing: 0) {
            settingRow(.muteSounds, "Mute Sounds", checked: model.muted)
                .quickHelp("Mute completion, waiting and error sounds. Focus integration is not enabled in this preview.")
            settingRow(.launchAtLogin, "Launch at Login", checked: model.launchAtLogin)
                .quickHelp(model.loginNeedsApproval ? "Approval required in System Settings" : "Start Status Board when you log in")
            Divider().padding(.horizontal, 3).padding(.vertical, 4)
            settingRow(.info, "Info", checked: nil)
            settingRow(.quit, "Quit", checked: nil)
        }.padding(5).frame(width: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.primary.opacity(0.12), lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.18), radius: 11, x: 0, y: 4)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { model.menuFrame = $0 }
            .accessibilityElement(children: .contain).accessibilityLabel("Settings menu")
    }
    private func settingRow(_ setting: BoardSetting, _ title: String, checked: Bool?) -> some View {
        Button { model.selectSetting(setting.rawValue) } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .medium))
                    .opacity(checked == true ? 1 : 0).frame(width: 14).accessibilityHidden(true)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: 32).contentShape(RoundedRectangle(cornerRadius: 6))
                .background(model.menuSelection == setting.rawValue ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).onHover { if $0 { model.menuSelection = setting.rawValue } }
            .accessibilityLabel(title).accessibilityValue(checked.map { $0 ? "On" : "Off" } ?? "")
    }
    private func count(_ value: Int?, label: String, tint: Color, unread: Bool = false) -> some View {
        Button(action: model.openCodex) {
            VStack(spacing: 5) {
                Text(value.map(String.init) ?? "—").font(.system(size: 20, weight: .medium)).monospacedDigit()
                    .overlay(alignment: .trailing) {
                        if unread { Circle().fill(BoardPalette.blue(dark)).frame(width: 5, height: 5).offset(x: 9).accessibilityHidden(true) }
                    }
                Text(label).font(.system(size: 11)).foregroundStyle(model.connected ? tint : mutedText)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }.frame(maxWidth: .infinity).frame(height: 54).contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(BoardControlStyle())
            .background { PointingHandArea(enabled: model.detailsExpanded && model.animatedDetailsProgress == nil && !model.settingsOpen) }
            .accessibilityLabel("\(value.map(String.init) ?? "Unavailable") \(label == "Done" ? "completed and unread" : label). Open Codex.")
    }
    private func quotaRow(_ quota: QuotaWindow) -> some View {
        let tone = model.usageIsSaved ? mutedText : quota.tone == .green ? BoardPalette.green(dark) : quota.tone == .orange ? BoardPalette.orange(dark) : BoardPalette.red(dark)
        return VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.label + (model.usageIsSaved ? " · Saved" : "")).font(.system(size: 12)).foregroundStyle(mutedText)
                Spacer()
                Text("\(quota.remaining)%").font(.system(size: 14, weight: .medium)).monospacedDigit().foregroundStyle(tone)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(tone).frame(width: geometry.size.width * Double(quota.remaining) / 100)
                }
            }.frame(height: 4)
        }.frame(height: 29)
            .focusable()
            .quickHelp(TimeLabel.text(prefix: "Reset at", date: quota.resetAt))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.usageIsSaved ? "Saved usage. " : "")\(quota.label), \(quota.remaining) percent. \(TimeLabel.text(prefix: "Reset at", date: quota.resetAt))")
    }
}

private struct BoardControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoveredControl(configuration: configuration) }
    private struct HoveredControl: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label.background(Color.primary.opacity(configuration.isPressed ? 0.15 : hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 9))
                .onHover { hovering = $0 }
        }
    }
}

