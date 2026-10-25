import Foundation
import Testing
@testable import StatusBoardCore

@Test(arguments: [(59.0, 41, QuotaTone.green), (60.0, 40, .orange), (79.0, 21, .orange),
                  (80.0, 20, .red), (59.1, 40, .orange), (79.1, 20, .red), (100.0, 0, .red), (0.0, 100, .green)])
func quotaDisplayAndColorShareRounding(used: Double, expected: Int, tone: QuotaTone) throws {
    let quota = try #require(QuotaWindow(key: "test", durationMinutes: 300, usedPercent: used, resetAt: nil))
    #expect(quota.remaining == expected)
    #expect(quota.tone == tone)
    #expect(quota.label == "5-hour remaining")
}
@Test(arguments: [Double.nan, Double.infinity, -1.0, 101.0])
func invalidQuotaIsUnavailable(used: Double) {
    #expect(QuotaWindow(key: "test", durationMinutes: 300, usedPercent: used, resetAt: nil) == nil)
}
@Test func quotaUsesSourceDuration() {
    #expect(QuotaWindow(key: "test", durationMinutes: 90, usedPercent: 10, resetAt: nil)?.label == "90-minute remaining")
    #expect(QuotaWindow(key: "test", durationMinutes: nil, usedPercent: 10, resetAt: nil) == nil)
    #expect(QuotaWindow(key: "test", label: "Special remaining", durationMinutes: nil, usedPercent: 10, resetAt: nil)?.label == "Special remaining")
}
@Test func timestampsAreExplicitAndLocal() {
    #expect(TimeLabel.text(prefix: "Reset at", date: nil) == "Reset at —")
    let date = Date(timeIntervalSince1970: 0)
    #expect(TimeLabel.text(prefix: "Last updated", date: date, timeZone: TimeZone(secondsFromGMT: 0)!).contains("Jan 1, 1970"))
    #expect(TimeLabel.text(prefix: "Last updated", date: date, timeZone: TimeZone(secondsFromGMT: -18000)!).contains("Dec 31, 1969"))
}
