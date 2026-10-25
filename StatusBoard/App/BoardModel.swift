import AppKit
import SwiftUI
import StatusBoardCore
import StatusBoardDesktop

enum BoardSetting: Int, CaseIterable { case muteSounds, launchAtLogin, info, quit }

@MainActor
final class BoardModel: ObservableObject {
    @Published var presentation = DashboardPresentation()
    @Published var now = Date()
    @Published var pinned = false
    @Published var expanded = false
    @Published var detailsExpanded = true
    @Published var animatedDetailsProgress: CGFloat?
    var detailsProgress: CGFloat { animatedDetailsProgress ?? (detailsExpanded ? 1 : 0) }
    @Published var settingsOpen = false
    @Published var menuSelection: Int?
    @Published var muted = false
    @Published var launchAtLogin = false
    @Published var loginNeedsApproval = false
    var menuFrame = CGRect.zero
    var gearFrame = CGRect.zero
    var selectSetting: (Int) -> Void = { _ in }
    var toggleSettings: () -> Void = {}
    var snapshot: LiveSnapshot { presentation.visibleSnapshot(at: now) ?? presentation.latest }
    var infoText: String {
        "Connection: \(connectionLabel)\n\n" +
        "Confirmed live conversations: \(snapshot.covered)/\(snapshot.total).\n" +
        "Current account, local, unarchived, top-level conversations only. Unsynchronized conversations are not counted; \(snapshot.unassigned) legacy conversations have no verified account.\n\n" +
        (snapshot.features.isEmpty ? snapshot.message : snapshot.featuresSummary) + "\n\n" +
        "Codex build: \(snapshot.codexBuild ?? "unknown") · compatibility checked per feature.\n\n" +
        TimeLabel.text(prefix: "Last complete sync", date: presentation.lastCompleteSyncAt)
    }
    var connected: Bool { presentation.visibleSnapshot(at: now) != nil }
    var usageIsSaved: Bool { !connected || snapshot.quotaUpdatedAt == nil || snapshot.features[.quota]?.state == .saved }
    var windows: [QuotaWindow] { presentation.windows(at: now) }
    var agents: [ProcessingAgent] {
        guard let snapshot = presentation.visibleSnapshot(at: now), (snapshot.counts?.processing ?? 0) > 0 else { return [] }
        return snapshot.agents
    }
    var agentsHeight: CGFloat { agents.isEmpty ? 0 : 21 + CGFloat(min(5, agents.count)) * 20 }
    var detailsHeight: CGFloat { 132 + CGFloat(max(1, windows.count) - 1) * 43 + agentsHeight }
    var cardHeight: CGFloat { 140 + detailsHeight * detailsProgress }
    static let avatarOverhang = CGSize(width: 8, height: 28)
    var panelSize: NSSize {
        expanded ? NSSize(width: 320 + Self.avatarOverhang.width, height: cardHeight + Self.avatarOverhang.height)
            : NSSize(width: 54, height: 54)
    }
    var connectionLabel: String {
        presentation.connectionLabel(at: now)
    }
    var icon = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Codex")!
    let avatar = Bundle.main.url(forResource: "dinosaur-cute", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
        ?? NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Avatar")!
    var togglePin: () -> Void = {}
    var toggleExpanded: () -> Void = {}
    var toggleDetails: () -> Void = {}
    var openCodex: () -> Void = {}
    var requestQuit: () -> Void = {}
    var counts: TaskCounts? { presentation.visibleSnapshot(at: now)?.counts }
    var compactStatus: CompactStatus? {
        guard let snapshot = presentation.visibleSnapshot(at: now), let counts = snapshot.counts else { return nil }
        if let status = snapshot.compactStatus, (status == .waiting ? counts.waiting : counts.done) > 0 { return status }
        return CompactStatus.baseline(counts)
    }
    var compactAccessibilityLabel: String {
        guard connected else { return "Open Codex status. \(connectionLabel)." }
        guard let counts else { return "Open Codex status. \(connectionLabel). \(snapshot.features[.tasks]?.detail ?? "Waiting for conversation data")." }
        switch compactStatus {
        case .waiting: return "Open Codex status. Latest status: Waiting for operation. \(counts.waiting) tasks waiting."
        case .done: return "Open Codex status. Latest status: Done. \(counts.done) unread completed tasks."
        case nil: return "Open Codex status. No tasks waiting or unread completions."
        }
    }
}

@MainActor
final class BoardPanel: NSPanel {
    var onMouseDown: (() -> Void)?
    let handCursorViews = NSHashTable<PointingHandArea.CursorView>.weakObjects()
    private var ownsHandCursor = false
    private var lastPointer: NSPoint?
    func clearHandCursor() {
        if ownsHandCursor { NSCursor.arrow.set() }
        ownsHandCursor = false
    }
    func refreshHandCursor() {
        guard lastPointer != nil,
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == windowNumber else { return }
        updateHandCursor(at: mouseLocationOutsideOfEventStream)
    }
    func updateHandCursor(at point: NSPoint) {
        if let contentView, contentView.bounds.contains(contentView.convert(point, from: nil)) { lastPointer = point }
        else { lastPointer = nil }
        let inside = handCursorViews.allObjects.contains { view in
            view.enabled && !view.isHiddenOrHasHiddenAncestor && view.window === self
                && view.visibleRect.contains(view.convert(point, from: nil))
        }
        if inside { NSCursor.pointingHand.set(); ownsHandCursor = true }
        else { clearHandCursor() }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel].contains(event.type) { QuickHelpController.shared.dismiss() }
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onMouseDown?() }
        super.sendEvent(event)
        // SwiftUI hosting can overwrite child cursor rectangles. Apply the
        // count-cell cursor last, without pushing onto the global cursor stack.
        if [.mouseMoved, .cursorUpdate, .mouseEntered, .mouseExited].contains(event.type) {
            updateHandCursor(at: event.locationInWindow)
        }
    }
}

