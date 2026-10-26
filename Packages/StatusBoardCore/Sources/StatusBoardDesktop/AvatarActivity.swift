import Foundation

/// Polling and reconnects are not activity. Only observed conversation changes
/// or fresh evidence of running work keep the dashboard avatar awake.
public struct AvatarActivity: Sendable {
    public static let sleepDelay: TimeInterval = 30 * 60
    private var lastActivityAt: Date

    public init(now: Date = Date()) { lastActivityAt = now }

    public mutating func receive(_ snapshot: LiveSnapshot, at now: Date) {
        if let activity = snapshot.lastCodexActivityAt {
            lastActivityAt = max(lastActivityAt, min(activity, now))
        }
        if snapshot.isConnected, (snapshot.counts?.processing ?? 0) > 0,
           now.timeIntervalSince(snapshot.updatedAt) <= 10 {
            lastActivityAt = max(lastActivityAt, min(snapshot.updatedAt, now))
        }
    }

    public func isSleeping(at now: Date) -> Bool {
        now.timeIntervalSince(lastActivityAt) >= Self.sleepDelay
    }
}
