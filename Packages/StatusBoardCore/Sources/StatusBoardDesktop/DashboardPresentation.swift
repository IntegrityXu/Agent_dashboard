import Foundation
import StatusBoardCore

/// Only quota metadata is persisted. A verified matching account is required
/// before a saved value can become visible; task counts are never cached.
public struct SavedUsage: Codable, Equatable, Sendable {
    public let account: String
    public let windows: [QuotaWindow]
    public let quotaReadAt: Date
    public let lastCompleteSyncAt: Date?
    public var isValid: Bool {
        !account.isEmpty && windows.allSatisfy(\.isValid)
        && Set(windows.map(\.key)).count == windows.count
        && quotaReadAt.timeIntervalSince1970.isFinite
        && (lastCompleteSyncAt?.timeIntervalSince1970.isFinite ?? true)
    }
}

public struct DashboardPresentation: Sendable {
    public private(set) var latest = LiveSnapshot()
    public private(set) var saved: SavedUsage?
    private var live: LiveSnapshot?
    private var failureAt: Date?
    public init(saved: SavedUsage? = nil) { self.saved = saved?.isValid == true ? saved : nil }
    public mutating func receive(_ snapshot: LiveSnapshot) {
        if latest.accountFingerprint != snapshot.accountFingerprint { live = nil; failureAt = nil }
        latest = snapshot
        guard let account = snapshot.accountFingerprint else { live = nil; failureAt = nil; return }
        if snapshot.isConnected {
            live = snapshot; failureAt = nil
            if let date = snapshot.quotaUpdatedAt {
                saved = SavedUsage(account: account, windows: snapshot.quota, quotaReadAt: date,
                    lastCompleteSyncAt: snapshot.lastCompleteSyncAt ?? (saved?.account == account ? saved?.lastCompleteSyncAt : nil))
            }
        } else if failureAt == nil { failureAt = snapshot.updatedAt }
    }
    public func visibleSnapshot(at now: Date) -> LiveSnapshot? {
        guard latest.compatibilityIssue == nil else { return nil }
        if !latest.isConnected && latest.features[.tasks]?.isDegraded == true { return nil }
        guard let live, live.accountFingerprint == latest.accountFingerprint,
              now.timeIntervalSince(live.updatedAt) <= 10 else { return nil }
        if latest.isConnected { return live }
        // Brief failures do not flash gray; continuous failures expire promptly.
        guard let failureAt, now.timeIntervalSince(failureAt) < 3 else { return nil }
        return live
    }
    public var verifiedSavedUsage: SavedUsage? {
        guard let account = latest.accountFingerprint, saved?.account == account else { return nil }
        return saved
    }
    public func windows(at now: Date) -> [QuotaWindow] {
        if let live = visibleSnapshot(at: now), live.quotaUpdatedAt != nil { return live.quota }
        return verifiedSavedUsage?.windows ?? []
    }
    public func connectionLabel(at now: Date) -> String {
        if let issue = latest.compatibilityIssue { return issue.label }
        if visibleSnapshot(at: now) != nil, latest.features.values.contains(where: \.isDegraded) { return "Connected · Limited" }
        return visibleSnapshot(at: now) != nil ? "Connected" : verifiedSavedUsage?.windows.isEmpty != false ? "Disconnected" : "Disconnected · Saved usage"
    }
    public var lastCompleteSyncAt: Date? { verifiedSavedUsage?.lastCompleteSyncAt }
}
