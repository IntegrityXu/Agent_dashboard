import Foundation
import StatusBoardCore

/// Build metadata is diagnostic only. Each data source validates its own contract.
enum DesktopCompatibility {
    static func build(applicationURL: URL) -> String? {
        // Read fresh on each reconnect; Bundle may cache an in-place update.
        let data = try? Data(contentsOf: applicationURL.appendingPathComponent("Contents/Info.plist"))
        let info = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        return info?["CFBundleVersion"] as? String
    }
}

public enum DesktopCompatibilityIssue: Error, Equatable, Sendable {
    case incompatibleProtocol
    public var label: String { "Incompatible Codex data" }
    public var message: String {
        "Codex returned an unsupported protocol or data format. Update Status Board to restore compatibility."
    }
}

extension LiveSnapshot {
    static func failure(_ error: Error) -> LiveSnapshot {
        var snapshot = LiveSnapshot()
        snapshot.compatibilityIssue = (error as? DesktopCompatibilityIssue)
            ?? ((error as? DesktopFailure) == .unsupported ? .incompatibleProtocol : nil)
        if let issue = snapshot.compatibilityIssue {
            snapshot.message = issue.message
        } else if (error as? DesktopStreamError) == .oversize {
            snapshot.message = "Codex status metadata exceeds safety limit · retrying"
        } else {
            snapshot.message = "Disconnected · retrying"
        }
        return snapshot
    }
}
