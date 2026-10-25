import Foundation

public enum TaskState: String, Codable, Sendable {
    case processing, waitingUser, waitingError, completed, stopped, idle, unknown
}
public struct TaskCounts: Equatable, Sendable {
    public var processing: Int = 0
    public var waiting: Int = 0
    public var done: Int = 0
    public init(processing: Int = 0, waiting: Int = 0, done: Int = 0) {
        self.processing = processing; self.waiting = waiting; self.done = done
    }
}

public enum QuotaTone: Sendable { case green, orange, red }
public struct QuotaWindow: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let remaining: Int
    public let resetAt: Date?
    public init?(key: String, label: String? = nil, durationMinutes: Int?, usedPercent: Double, resetAt: Date?) {
        guard !key.isEmpty, usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
        let authoritative = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let authoritative, !authoritative.isEmpty { self.label = authoritative }
        else if let durationMinutes, durationMinutes > 0 {
            if durationMinutes == 10080 { self.label = "Weekly remaining" }
            else if durationMinutes % 1440 == 0 { self.label = "\(durationMinutes / 1440)-day remaining" }
            else if durationMinutes % 60 == 0 { self.label = "\(durationMinutes / 60)-hour remaining" }
            else { self.label = "\(durationMinutes)-minute remaining" }
        } else { return nil }
        self.key = key; self.remaining = Int(floor(100 - usedPercent)); self.resetAt = resetAt
    }
    public var tone: QuotaTone { remaining > 40 ? .green : remaining > 20 ? .orange : .red }
    public var isValid: Bool { !key.isEmpty && !label.isEmpty && (0...100).contains(remaining) }
}

public enum TimeLabel {
    public static func text(prefix: String, date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "\(prefix) —" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy, h:mm a z"
        return "\(prefix) \(formatter.string(from: date))"
    }
}
