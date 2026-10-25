import Foundation
import StatusBoardCore

/// Decode before committing: malformed windows must not erase verified usage.
/// Missing/null windows and a map without the Codex bucket are valid empty data.
enum QuotaDecoder {
    private struct Response: Decodable {
        let rateLimits: Bucket
        let rateLimitsByLimitId: [String: Bucket]?
    }
    private struct Bucket: Decodable {
        let primary: Window?
        let secondary: Window?
    }
    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Int64?
    }
    static func decode(_ response: [String: Any]) throws -> [QuotaWindow] {
        do {
            let decoded = try JSONDecoder().decode(Response.self,
                from: JSONSerialization.data(withJSONObject: response))
            let bucket = decoded.rateLimitsByLimitId.map { $0["codex"] } ?? decoded.rateLimits
            guard let bucket else { return [] }
            return try [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { key, window in
                guard let window else { return nil }
                guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
                      window.windowDurationMins.map({ $0 > 0 }) ?? true else { throw DesktopFailure.unsupported }
                // The protocol permits an unknown duration. Do not invent a label.
                guard let duration = window.windowDurationMins else { return nil }
                return QuotaWindow(key: key, durationMinutes: duration, usedPercent: window.usedPercent,
                    resetAt: window.resetsAt.map { Date(timeIntervalSince1970: Double($0)) })
            }
        } catch { throw DesktopFailure.unsupported }
    }
}
