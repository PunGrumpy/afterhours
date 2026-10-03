import Foundation
import Testing
@testable import AfterhoursCore

@Test func startTimeOfThisProcessIsRecentAndInThePast() throws {
    let start = try #require(Proc.startTime(getpid()))
    #expect(start <= Date())
    #expect(Date().timeIntervalSince(start) < 24 * 3600)
}

@Test func startTimeIsNilForAPidThatDoesNotExist() {
    #expect(Proc.startTime(99_999_999) == nil)
}

@Test func cpuSinceLastScanCountsOnlyWorkDoneSinceThatScan() {
    let lastScan = Date(timeIntervalSince1970: 1_790_000_000)
    let before = lastScan.addingTimeInterval(-3600)
    let after = lastScan.addingTimeInterval(1)
    // Sampled last time: the difference, never negative.
    #expect(Proc.cpuSinceLastScan(current: 900, previous: 400, startedAt: nil, lastScan: lastScan) == 500)
    #expect(Proc.cpuSinceLastScan(current: 300, previous: 400, startedAt: nil, lastScan: lastScan) == 0)
    // Started since the last scan: all of it is new.
    #expect(Proc.cpuSinceLastScan(current: 900, previous: nil, startedAt: after, lastScan: lastScan) == 900)
    // Already running but never sampled, like an agent whose detection was just turned on: a baseline only.
    #expect(Proc.cpuSinceLastScan(current: 900, previous: nil, startedAt: before, lastScan: lastScan) == 0)
    #expect(Proc.cpuSinceLastScan(current: 900, previous: nil, startedAt: nil, lastScan: lastScan) == 0)
    #expect(Proc.cpuSinceLastScan(current: 900, previous: nil, startedAt: after, lastScan: nil) == 0)
}
