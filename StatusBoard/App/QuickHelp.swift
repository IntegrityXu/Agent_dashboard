import AppKit
import SwiftUI

/// App-local help timing; no system-wide tooltip preferences are changed.
@MainActor
final class QuickHelpController {
    static let shared = QuickHelpController()
    static let delay: TimeInterval = 0.35
    private var timer: Timer?
    private var owner: UUID?
    private var text = ""
    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible == true }

    func schedule(_ text: String, owner: UUID) {
        if self.owner == owner { update(text, owner: owner); return }
        dismiss()
        guard !text.isEmpty else { return }
        self.owner = owner; self.text = text
        let timer = Timer(timeInterval: Self.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.owner == owner else { return }
                self.timer = nil
                self.show()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func update(_ text: String, owner: UUID) {
        guard self.owner == owner, self.text != text else { return }
        self.text = text
        if text.isEmpty { dismiss() }
        else if isVisible { show() }
    }

    func cancel(owner: UUID) {
        if self.owner == owner { dismiss() }
    }

    func dismiss() {
        timer?.invalidate(); timer = nil; owner = nil
        panel?.orderOut(nil)
    }

    private func show() {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = min(300, max(1, ceil((text as NSString).size(withAttributes: attributes).width)))
        let height = ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height)
        let size = NSSize(width: width + 16, height: height + 12)
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font; label.textColor = .labelColor
        label.frame = NSRect(x: 8, y: 6, width: width, height: height)
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        background.addSubview(label)
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.isOpaque = false
            window.backgroundColor = .clear; window.hasShadow = true
            window.ignoresMouseEvents = true; window.level = .popUpMenu
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel = window
        }
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 16)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            let visible = screen.visibleFrame.insetBy(dx: 4, dy: 4)
            if origin.y < visible.minY { origin.y = mouse.y + 20 }
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.contentView = background
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

private struct QuickHelp: ViewModifier {
    let text: String
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        content
            .accessibilityHint(text)
            .onHover { inside in
                if inside { QuickHelpController.shared.schedule(text, owner: owner) }
                else { QuickHelpController.shared.cancel(owner: owner) }
            }
            .onChange(of: text) { _, value in QuickHelpController.shared.update(value, owner: owner) }
            .onDisappear { QuickHelpController.shared.cancel(owner: owner) }
    }
}

extension View {
    func quickHelp(_ text: String) -> some View { modifier(QuickHelp(text: text)) }
}
