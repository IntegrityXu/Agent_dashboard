import Foundation
import StatusBoardCore

public struct LiveSnapshot: Sendable {
    // Event payloads are one-shot, independent of restored counts/read state.
    public var audioGeneration: UUID?
    public var audioEvents: [LiveAlert] = []
    public var invalidatedAudioThreads = Set<String>()
    public var isConnected = false
    public var codexBuild: String?
    public var features: [DesktopFeature: FeatureStatus] = [:]
    public var compatibilityIssue: DesktopCompatibilityIssue?
    public var lastCompleteSyncAt: Date?
    public var counts: TaskCounts?
    public var compactStatus: CompactStatus?
    public var agents: [ProcessingAgent] = []
    public var covered = 0
    public var total = 0
    public var unassigned = 0
    public var restoredDone = 0
    public var restoredCompleted = 0
    public var quota: [QuotaWindow] = []
    public var quotaUpdatedAt: Date?
    public var updatedAt = Date()
    public var accountFingerprint: String?
    public var message = "Connecting to Codex…"
    public init() {}
    public var partial: Bool { covered < total || unassigned > 0 }

    /// Desktop connectivity is independent of lazy conversation loading. After
    /// a restart, a verified IPC session may have no classifiable streams until a
    /// conversation opens. Keep unknown counts unavailable instead of zero.
    static func session(initialized: Bool, observations: [DesktopObservation], total: Int, unassigned: Int,
                        restoredDone: Int = 0, restoredCompleted: Int = 0,
                        quota: [QuotaWindow], quotaDate: Date?, accountFingerprint: String) -> LiveSnapshot {
        var (counts, covered) = LiveClassification.counts(observations)
        counts.done += restoredDone
        var snapshot = LiveSnapshot()
        snapshot.isConnected = initialized
        snapshot.counts = snapshot.isConnected && (covered > 0 || restoredCompleted > 0 || restoredDone > 0 || total == 0) ? counts : nil
        snapshot.compactStatus = CompactStatus.baseline(snapshot.counts)
        snapshot.restoredDone = restoredDone
        snapshot.restoredCompleted = restoredCompleted
        snapshot.lastCompleteSyncAt = snapshot.isConnected && covered == total && unassigned == 0 ? quotaDate : nil
        snapshot.covered = covered; snapshot.total = total; snapshot.unassigned = unassigned
        snapshot.quota = quota; snapshot.quotaUpdatedAt = quotaDate
        snapshot.accountFingerprint = accountFingerprint
        snapshot.message = !snapshot.isConnected ? "Connecting to Codex…"
            : restoredDone > 0 ? "Live · includes unread completions restored from Codex"
            : restoredCompleted > 0 ? "Live · includes completed conversations restored from Codex"
            : covered == 0 && total > 0 ? "Connected · waiting for conversation data"
            : snapshot.partial ? "Live · partial coverage" : "Live"
        return snapshot
    }
}

public enum LiveClassification {
    public static func state(_ observation: DesktopObservation) -> TaskState {
        if observation.isWaitingForUser { return .waitingUser }
        if observation.hasUnclassifiedRequests { return .unknown }
        if observation.runtime == "active" { return .processing }
        if observation.runtime == "systemError" { return .waitingError }
        switch observation.status {
        case "inProgress": return .processing
        case "failed": return .waitingError
        case "interrupted": return .stopped
        // Heartbeat alert suppression belongs to DesktopStream, not counting.
        case "completed": return observation.unread == nil ? .unknown : .completed
        case nil: return observation.runtime == "idle" && observation.hasLatestTurnCoverage ? .idle : .unknown
        default: return .unknown
        }
    }
    public static func counts(_ observations: [DesktopObservation]) -> (TaskCounts, Int) {
        var counts = TaskCounts(), covered = 0
        for o in observations {
            switch state(o) {
            case .processing: counts.processing += 1
            case .waitingUser, .waitingError: counts.waiting += 1
            case .completed: if o.unread == true { counts.done += 1 }
            case .idle, .stopped: break
            case .unknown: continue
            }
            covered += 1
        }
        return (counts, covered)
    }
}
