import Foundation
import Testing
@testable import AfterhoursCore

private let fiveHours: TimeInterval = 5 * 3600

private func window(used: Double, resetsIn: TimeInterval?, now: Date) -> UsageWindow {
    UsageWindow(id: "five_hour", kind: .session, label: "Session", usedPercent: used,
                resetsAt: resetsIn.map { now.addingTimeInterval($0) }, duration: fiveHours)
}

@Test func usedPercentIsClampedToZeroThroughOneHundred() {
    let now = Date()
    #expect(window(used: -5, resetsIn: nil, now: now).usedPercent == 0)
    #expect(window(used: 150, resetsIn: nil, now: now).usedPercent == 100)
    #expect(window(used: .nan, resetsIn: nil, now: now).usedPercent == 0)
    #expect(window(used: 42.5, resetsIn: nil, now: now).leftPercent == 57.5)
}

@Test func paceNeedsAResetSomeUseAndAFewPercentOfTheWindow() {
    let now = Date()
    #expect(window(used: 30, resetsIn: nil, now: now).pace(now: now) == nil)
    #expect(window(used: 0, resetsIn: 9000, now: now).pace(now: now) == nil)
    // 1% of the window elapsed (resets in 99% of the duration): too young.
    #expect(window(used: 30, resetsIn: fiveHours * 0.99, now: now).pace(now: now) == nil)
}

@Test func paceProjectsTheBurnRateToTheReset() throws {
    let now = Date()
    let pace = try #require(window(used: 30, resetsIn: 9000, now: now).pace(now: now))
    #expect(abs(pace.elapsed - 0.5) < 0.0001)
    #expect(abs(pace.projectedLeft - 40) < 0.0001)
    #expect(pace.runsOutAt == nil)
}

@Test func paceReportsWhenTheWindowRunsOutBeforeTheReset() throws {
    let now = Date()
    let pace = try #require(window(used: 60, resetsIn: 9000, now: now).pace(now: now))
    #expect(abs(pace.projectedLeft - (-20)) < 0.0001)
    let runsOut = try #require(pace.runsOutAt)
    #expect(abs(runsOut.timeIntervalSince(now) - 6000) < 1)
}

@Test func kindsOrderSessionBeforeWeeklyBeforeMonthly() {
    #expect(UsageWindow.Kind.session < .weekly)
    #expect(UsageWindow.Kind.weekly < .monthly)
    #expect(UsageWindow.Kind.weekly.defaultDuration == 7 * 24 * 3600)
}

private func utc(_ text: String) throws -> Date { try #require(UsageLimits.parseISO8601(text)) }

private func monthly(used: Double, resetsAt: Date?) -> UsageWindow {
    UsageWindow(id: "chat", kind: .monthly, label: "Chat", usedPercent: used, resetsAt: resetsAt)
}

@Test func monthlyWindowsSpanTheCalendarMonthBeforeTheirReset() throws {
    let day: TimeInterval = 24 * 3600
    let march = try utc("2027-03-01T00:00:00Z")
    let november = try utc("2026-11-01T00:00:00Z")
    #expect(monthly(used: 10, resetsAt: march).duration == 28 * day)
    #expect(monthly(used: 10, resetsAt: november).duration == 31 * day)
    #expect(monthly(used: 10, resetsAt: nil).duration == 30 * day)
    #expect(UsageWindow(id: "s", kind: .session, label: "Session", usedPercent: 10, resetsAt: march).duration == fiveHours)
}

@Test func aFebruaryWindowThreeDaysInIsOnPaceToNearlyRunOut() throws {
    let window = monthly(used: 10, resetsAt: try utc("2027-03-01T00:00:00Z"))
    let pace = try #require(window.pace(now: try utc("2027-02-04T00:00:00Z")))
    #expect(abs(pace.elapsed - 3.0 / 28) < 0.0001)
    #expect(abs(pace.projectedLeft - (100 - 10 * 28.0 / 3)) < 0.01)
}
