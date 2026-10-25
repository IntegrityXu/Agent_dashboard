import Foundation
import StatusBoardCore

/// Transient live events only. Never persist these or derive them from counts.
public struct LiveAlert: Sendable {
    public let thread: String
    public let transition: DesktopTransition
    public let observedAt: Date
}

@MainActor
public protocol AlertPlayback: AnyObject {
    /// Completion must be asynchronous. A failed start is consumed, never retried.
    func play(_ kind: AlertKind, completion: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

/// Manual-mute preview policy. Focus is deliberately not represented as a
/// fabricated allowsAudio value: its system integration remains deferred.
@MainActor
public final class AudioNotifications {
    private let playback: any AlertPlayback
    private let clock: () -> Date
    private var generation: UUID?
    private var account: String?
    private var consumed = Set<String>()
    private var pending: [LiveAlert] = []
    private var current: LiveAlert?
    private var playbackToken: UUID?
    private var connected = false
    private var muted = false
    private var suspended = false
    private var stopped = false
    private var discardThrough = Date.distantPast
    private var lastUpdate = Date.distantPast
    public var pendingCount: Int { pending.count }
    public var isPlaying: Bool { current != nil }

    public init(playback: any AlertPlayback, clock: @escaping () -> Date = Date.init) {
        self.playback = playback; self.clock = clock
    }
    public func setMuted(_ value: Bool) {
        guard value != muted else { return }
        muted = value; discardThrough = clock()
        if value { cancel() }
    }
    public func setSuspended(_ value: Bool) {
        suspended = value; discardThrough = clock(); connected = false; cancel()
    }
    public func shutdown() { stopped = true; connected = false; cancel() }
    public func receive(_ snapshot: LiveSnapshot) {
        guard !stopped else { return }
        if let verified = snapshot.accountFingerprint, account != verified {
            account = verified; consumed.removeAll(); cancel()
        }
        if generation != snapshot.audioGeneration { cancel() }
        generation = snapshot.audioGeneration
        lastUpdate = snapshot.updatedAt
        connected = snapshot.isConnected && generation != nil && snapshot.accountFingerprint != nil
        if !connected { cancel() }
        let invalid = snapshot.invalidatedAudioThreads
        pending.removeAll { invalid.contains($0.thread) }
        if let current, invalid.contains(current.thread) { stopCurrent() }
        for event in snapshot.audioEvents {
            guard consumed.insert(event.transition.occurrence).inserted else { continue }
            // Consume even when suppressed. Never accumulate a catch-up queue.
            if allowed, isFresh(event) { pending.append(event) }
        }
        advance()
    }
    public func checkHealth() {
        if clock().timeIntervalSince(lastUpdate) > 10 { connected = false; cancel() }
    }
    private var allowed: Bool {
        connected && !muted && !suspended && !stopped && clock().timeIntervalSince(lastUpdate) <= 10
    }
    private func isFresh(_ event: LiveAlert) -> Bool {
        event.observedAt > discardThrough && clock().timeIntervalSince(event.observedAt) <= 10
    }
    private func advance() {
        guard current == nil else { return }
        guard allowed else { cancel(); return }
        while !pending.isEmpty {
            let event = pending.removeFirst()
            // Queueing must not extend an event's useful lifetime. Its identity
            // remains consumed even when playback is skipped.
            guard isFresh(event) else { continue }
            let token = UUID()
            current = event; playbackToken = token
            if playback.play(event.transition.kind, completion: { [weak self] in
                guard let self, self.playbackToken == token else { return }
                self.current = nil; self.playbackToken = nil; self.advance()
            }) { return }
            // A missing asset/device failure must not stall later events.
            current = nil; playbackToken = nil
        }
    }
    private func stopCurrent() {
        playbackToken = nil; current = nil; playback.stop()
    }
    private func cancel() { pending.removeAll(); stopCurrent() }
}
