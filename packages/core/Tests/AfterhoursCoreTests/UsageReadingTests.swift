import Foundation
import Testing
@testable import AfterhoursCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let readTime = now.addingTimeInterval(-3600)
private let oldReadTime = now.addingTimeInterval(-86400)

private func window(_ id: String, used: Double = 40, resetsIn hours: Double?, kind: UsageWindow.Kind = .session) -> UsageWindow {
    UsageWindow(id: id, kind: kind, label: "Label \(id)", usedPercent: used,
                resetsAt: hours.map { now.addingTimeInterval($0 * 3600) })
}

private func sample() -> UsageReading {
    let claude = UsageAccount(provider: "claude", plan: "Ultra", locations: ["~/.claude", "~/.claude-work"], windows: [
        window("five_hour", resetsIn: 2),
        window("seven_day", used: 70, resetsIn: 50, kind: .weekly),
        window("monthly_spend", used: 18, resetsIn: nil, kind: .monthly),
    ])
    let hubbed = UsageAccount(provider: "claude", plan: nil, locations: ["team@example.com"], source: "Thaipass", windows: [
        window("seven_day", used: 91, resetsIn: 30, kind: .weekly),
    ])
    let codex = UsageAccount(provider: "codex", plan: "Pro", locations: ["~/.codex"], windows: [
        window("primary", used: 12, resetsIn: 3),
    ])
    let accounts = [claude, hubbed, codex]
    return UsageReading(snapshot: UsageSnapshot(accounts: accounts),
                        readAt: [claude.id: readTime, hubbed.id: oldReadTime, codex.id: readTime])
}

private func roundTrip(_ reading: UsageReading, at date: Date = now) -> UsageReading? {
    reading.saved().flatMap { UsageReading(saved: $0, now: date) }
}

private func decoded(_ json: String) -> UsageReading? {
    UsageReading(saved: Data(json.utf8), now: now)
}

@Test func aSavedReadingComesBackWithEveryAccountWindowAndTime() throws {
    let reading = sample()
    let restored = try #require(roundTrip(reading))
    #expect(restored == reading)
    #expect(restored.snapshot.accounts.map(\.plan) == ["Ultra", nil, "Pro"])
    #expect(restored.snapshot.accounts[1].source == "Thaipass")
    #expect(restored.snapshot.accounts[0].locations == ["~/.claude", "~/.claude-work"])
    #expect(restored.readAt == reading.readAt)
}

@Test func aWindowThatResetBeforeNowIsDroppedWhenRestoring() throws {
    var reading = sample()
    let claude = reading.snapshot.accounts[0]
    reading.snapshot.accounts[0] = UsageAccount(provider: "claude", plan: "Ultra", locations: claude.locations, windows: [
        window("five_hour", resetsIn: -1),
        window("seven_day", used: 70, resetsIn: 50, kind: .weekly),
    ])
    reading.readAt[reading.snapshot.accounts[0].id] = readTime
    let restored = try #require(roundTrip(reading))
    #expect(restored.snapshot.accounts[0].windows.map(\.id) == ["seven_day"])
}

@Test func anAccountLeftWithNoWindowsIsDropped() throws {
    var reading = sample()
    let codex = reading.snapshot.accounts[2]
    reading.snapshot.accounts[2] = UsageAccount(provider: "codex", plan: "Pro", locations: codex.locations,
                                                windows: [window("primary", resetsIn: -0.5)])
    let restored = try #require(roundTrip(reading))
    #expect(restored.snapshot.accounts.map(\.provider) == ["claude", "claude"])
    #expect(restored.readAt[codex.id] == nil)
}

@Test func aWindowWithNoResetTimeIsKept() throws {
    let restored = try #require(roundTrip(sample(), at: now.addingTimeInterval(86400 * 365)))
    let spend = restored.snapshot.accounts.first?.windows.first { $0.id == "monthly_spend" }
    #expect(spend?.usedPercent == 18)
    #expect(spend?.resetsAt == nil)
}

@Test func garbageAnEmptyFileAndOtherVersionsGiveNothing() {
    #expect(UsageReading(saved: Data([0x00, 0xFF, 0x10, 0x42]), now: now) == nil)
    #expect(UsageReading(saved: Data(), now: now) == nil)
    #expect(decoded(#"{"version":2,"accounts":[]}"#) == nil)
    #expect(decoded(#"{"version":0,"accounts":[]}"#) == nil)
    #expect(decoded(#"{"accounts":[]}"#) == nil)
    #expect(decoded(#"{"version":1}"#) == nil)
    #expect(decoded(#"{"version":1,"accounts":[]}"#) != nil)
}

@Test func theSavedBytesHoldNoErrorTextAndNoHubError() throws {
    let carried = UsageAccount(provider: "claude", plan: "Ultra", locations: ["~/.claude"],
                               windows: [window("five_hour", resetsIn: 2)],
                               error: "Token rejected, run claude to sign in again")
    let failed = UsageAccount(provider: "codex", plan: nil, locations: ["~/.codex"], windows: [],
                              error: "Codex returned HTTP 500 for sk-secret-value")
    let snapshot = UsageSnapshot(accounts: [carried, failed], hubErrors: ["Spare hub: The hub rejected the management key"])
    let reading = UsageReading(snapshot: snapshot, readAt: [carried.id: readTime])
    let text = try #require(reading.saved().flatMap { String(data: $0, encoding: .utf8) })
    #expect(!text.contains("Token rejected"))
    #expect(!text.contains("sk-secret-value"))
    #expect(!text.contains("HTTP 500"))
    #expect(!text.contains("management key"))
    #expect(!text.contains("error"))
    let restored = try #require(UsageReading(saved: Data(text.utf8), now: now))
    #expect(restored.snapshot.accounts.map(\.provider) == ["claude"])
    #expect(restored.snapshot.accounts[0].error == nil)
    #expect(restored.snapshot.hubErrors.isEmpty)
}

@Test func anAccountWithNoSuccessfulReadIsNotSaved() throws {
    let account = UsageAccount(provider: "codex", plan: nil, locations: ["~/.codex"], windows: [window("primary", resetsIn: 2)])
    let reading = UsageReading(snapshot: UsageSnapshot(accounts: [account]), readAt: [:])
    let restored = try #require(roundTrip(reading))
    #expect(restored.snapshot.accounts.isEmpty)
}

@Test func anOutOfRangeShareInTheFileComesBackClamped() throws {
    let json = """
    {"version":1,"accounts":[{"provider":"claude","plan":"Pro","locations":["~/.claude"],
    "readAt":"2027-01-15T07:00:00Z","windows":[
    {"id":"a","kind":0,"label":"Session","usedPercent":250,"resetsAt":"2027-01-15T10:00:00Z","duration":18000},
    {"id":"b","kind":1,"label":"Weekly","usedPercent":-5,"resetsAt":null,"duration":604800}]}]}
    """
    let restored = try #require(decoded(json))
    #expect(restored.snapshot.accounts[0].windows.map(\.usedPercent) == [100, 0])
}

@Test func aWindowOfAnUnknownKindIsLeftOut() throws {
    let json = """
    {"version":1,"accounts":[{"provider":"claude","plan":null,"locations":["~/.claude"],
    "readAt":"2027-01-15T07:00:00Z","windows":[
    {"id":"a","kind":9,"label":"Odd","usedPercent":10,"resetsAt":null,"duration":0},
    {"id":"b","kind":1,"label":"Weekly","usedPercent":20,"resetsAt":null,"duration":604800}]}]}
    """
    let restored = try #require(decoded(json))
    #expect(restored.snapshot.accounts[0].windows.map(\.id) == ["b"])
}

@Test func asOfIsTheOldestReadAmongTheAccountsShown() {
    let reading = sample()
    #expect(reading.asOf == oldReadTime)
    var withoutTheOldest = reading
    withoutTheOldest.snapshot.accounts.remove(at: 1)
    #expect(withoutTheOldest.asOf == readTime)
    #expect(UsageReading().asOf == nil)
}

@Test func asOfIgnoresATimeForAnAccountThatIsNotShown() {
    var reading = sample()
    reading.readAt["local:gone:~/.gone"] = now.addingTimeInterval(-9 * 86400)
    #expect(reading.asOf == oldReadTime)
}

@Test func currentDropsPassedWindowsThenEmptyAccounts() {
    let reading = sample()
    let later = now.addingTimeInterval(3.5 * 3600)
    let current = reading.current(at: later)
    #expect(current.snapshot.accounts.first?.windows.map(\.id) == ["seven_day", "monthly_spend"])
    #expect(current.snapshot.accounts.map(\.provider) == ["claude", "claude"])
    #expect(current.readAt.count == 2)
}

@Test func currentKeepsAnAccountThatStillHasAnErrorToShow() {
    let failed = UsageAccount(provider: "codex", plan: nil, locations: ["~/.codex"], windows: [], error: "Not signed in")
    let reading = UsageReading(snapshot: UsageSnapshot(accounts: [failed], hubErrors: ["Hub: down"]), readAt: [:])
    #expect(reading.current(at: now) == reading)
}

@Test func currentTwiceGivesTheSameResultAsOnce() {
    let reading = sample()
    let later = now.addingTimeInterval(3.5 * 3600)
    #expect(reading.current(at: later).current(at: later) == reading.current(at: later))
}

@Test func aSavedAccountWithNoLocationsIsSkipped() throws {
    let json = """
    {"version":1,"accounts":[
    {"provider":"claude","plan":null,"locations":[],"readAt":"2027-01-15T07:00:00Z","windows":[
    {"id":"a","kind":1,"label":"Weekly","usedPercent":20,"resetsAt":null,"duration":604800}]},
    {"provider":"codex","plan":null,"locations":["~/.codex"],"readAt":"2027-01-15T07:00:00Z","windows":[
    {"id":"b","kind":1,"label":"Weekly","usedPercent":30,"resetsAt":null,"duration":604800}]}]}
    """
    let restored = try #require(decoded(json))
    #expect(restored.snapshot.accounts.map(\.provider) == ["codex"])
}

private func failed(_ provider: String = "claude") -> UsageAccount {
    UsageAccount(provider: provider, plan: nil, locations: ["~/.\(provider)"], windows: [], error: "No network")
}

private func succeeded(_ provider: String = "claude") -> UsageAccount {
    UsageAccount(provider: provider, plan: nil, locations: ["~/.\(provider)"], windows: [window("w", resetsIn: 2)])
}

@Test func aReadWithOneSuccessWritesTheFile() {
    let fresh = UsageSnapshot(accounts: [failed("codex"), succeeded()], hubErrors: ["Thaipass is unreachable"])
    #expect(fresh.hasSuccess)
    #expect(UsageReading.fileAction(after: fresh) == .write)
}

@Test func aReadWhereEveryAccountFailedLeavesTheFileAlone() {
    let fresh = UsageSnapshot(accounts: [failed(), failed("codex")])
    #expect(!fresh.hasSuccess)
    #expect(UsageReading.fileAction(after: fresh) == .keep)
}

@Test func aReadWithOnlyHubErrorsLeavesTheFileAlone() {
    let fresh = UsageSnapshot(accounts: [], hubErrors: ["Thaipass is unreachable"])
    #expect(!fresh.hasSuccess)
    #expect(UsageReading.fileAction(after: fresh) == .keep)
}

@Test func aReadThatFindsNothingAtAllDeletesTheFile() {
    #expect(UsageReading.fileAction(after: UsageSnapshot()) == .delete)
}
