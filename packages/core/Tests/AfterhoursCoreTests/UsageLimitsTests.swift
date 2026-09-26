import Foundation
import Testing
@testable import AfterhoursCore

// MARK: - Hub URLs

@Test func hubURLAddsHTTPSAndTheManagementPath() {
    #expect(UsageLimits.hubURL("hub.example.com", path: "auth-files")?.absoluteString
            == "https://hub.example.com/v0/management/auth-files")
}

@Test func hubURLKeepsAnExplicitSchemeAndPort() {
    #expect(UsageLimits.hubURL("http://localhost:8317/", path: "api-call")?.absoluteString
            == "http://localhost:8317/v0/management/api-call")
}

@Test func hubURLDropsTrailingSlashAndQuery() {
    #expect(UsageLimits.hubURL("https://h/base/?q=1", path: "auth-files")?.absoluteString
            == "https://h/base/v0/management/auth-files")
}

@Test func hubURLRejectsOtherSchemes() {
    #expect(UsageLimits.hubURL("ftp://h", path: "auth-files") == nil)
}

// MARK: - Dates and text

@Test func parseISO8601AcceptsBothFractionalAndWholeSeconds() {
    #expect(UsageLimits.parseISO8601("2026-09-26T10:00:00.123Z") != nil)
    #expect(UsageLimits.parseISO8601("2026-09-26T10:00:00Z") != nil)
    #expect(UsageLimits.parseISO8601("tomorrow") == nil)
}

@Test func capitalizedUppercasesOnlyTheFirstCharacter() {
    #expect(UsageLimits.capitalized("pro") == "Pro")
    #expect(UsageLimits.capitalized("") == "")
}

// MARK: - Codex account id from the id token

private func jwt(payload: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let body = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(body).sig"
}

@Test func chatGPTAccountIdReadsTheOpenAIAuthClaim() {
    let token = jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "acct_123"]])
    #expect(UsageLimits.chatGPTAccountId(token) == "acct_123")
}

@Test func chatGPTAccountIdIsNilForMalformedTokens() {
    #expect(UsageLimits.chatGPTAccountId("not.a-jwt") == nil)
    #expect(UsageLimits.chatGPTAccountId(jwt(payload: ["sub": "x"])) == nil)
}

// MARK: - Claude usage

private let claudeFixture = Data("""
{
  "five_hour": {"utilization": 42.5, "resets_at": "2026-09-26T12:00:00.000Z"},
  "seven_day": {"utilization": 80, "resets_at": "2026-09-30T00:00:00Z"},
  "limits": [
    {"kind": "weekly_scoped", "percent": 55, "resets_at": "2026-09-30T00:00:00Z",
     "scope": {"model": {"display_name": "Fable"}}},
    {"kind": "other", "percent": 1}
  ]
}
""".utf8)

@Test func claudeAccountMapsSessionWeeklyAndScopedWindows() {
    let account = UsageLimits.claudeAccount(.success(claudeFixture), plan: "Max", locations: ["~/.claude"], source: nil)
    #expect(account.error == nil)
    #expect(account.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_fable"])
    #expect(account.windows.map(\.kind) == [.session, .weekly, .weekly])
    #expect(account.windows[2].label == "Weekly · Fable")
    #expect(account.windows[0].usedPercent == 42.5)
    #expect(account.windows[0].resetsAt != nil)
    #expect(account.id == "local:claude:~/.claude")
}

@Test func claudeAccountTurnsAuthFailuresIntoASignInHint() {
    let account = UsageLimits.claudeAccount(.failure(.status(401)), plan: nil, locations: ["~/.claude"], source: nil)
    #expect(account.windows.isEmpty)
    #expect(account.error == "Run claude once to refresh its login")
}

@Test func claudeAccountReportsUnreadableBodies() {
    let account = UsageLimits.claudeAccount(.success(Data("nope".utf8)), plan: nil, locations: ["~/.claude"], source: nil)
    #expect(account.error == "Couldn't read the usage response")
}

// MARK: - Codex usage

private let codexFixture = Data("""
{
  "plan_type": "pro",
  "rate_limit": {
    "primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790000000},
    "secondary_window": {"used_percent": 34, "limit_window_seconds": 604800, "reset_at": 1790400000}
  }
}
""".utf8)

@Test func codexAccountMapsBothWindowsWithTheirDurations() {
    let account = UsageLimits.codexAccount(.success(codexFixture), fallbackPlan: nil, locations: ["~/.codex"], source: nil)
    #expect(account.plan == "Pro")
    #expect(account.windows.map(\.id) == ["primary", "secondary"])
    #expect(account.windows.map(\.kind) == [.session, .weekly])
    #expect(account.windows.map(\.duration) == [18000, 604800])
    #expect(account.windows[0].resetsAt == Date(timeIntervalSince1970: 1_790_000_000))
}

@Test func codexAccountFallsBackToTheHubPlanWhenTheResponseHasNone() {
    let body = Data(#"{"rate_limit": {"primary_window": {"used_percent": 5}}}"#.utf8)
    let account = UsageLimits.codexAccount(.success(body), fallbackPlan: "plus", locations: ["a@b.c"], source: "Hub")
    #expect(account.plan == "Plus")
    #expect(account.windows.count == 1)
    #expect(account.windows[0].duration == 5 * 3600)
    #expect(account.id == "Hub:codex:a@b.c")
}

// MARK: - Merging logins that are one account

private func claude(_ location: String, used: Double, resetsAt: Date?) -> UsageAccount {
    UsageAccount(provider: "claude", plan: "Max", locations: [location], windows: [
        UsageWindow(id: "five_hour", kind: .session, label: "Session", usedPercent: used, resetsAt: resetsAt),
    ])
}

@Test func mergeFoldsLoginsThatReportTheSameShares() {
    let reset = Date(timeIntervalSince1970: 1_790_000_000)
    var accounts: [UsageAccount] = []
    UsageLimits.merge(claude("~/.claude", used: 40, resetsAt: reset), into: &accounts)
    UsageLimits.merge(claude("~/.claude-work", used: 40, resetsAt: reset.addingTimeInterval(0.4)), into: &accounts)
    #expect(accounts.count == 1)
    #expect(accounts[0].locations == ["~/.claude", "~/.claude-work"])
}

@Test func mergeKeepsAccountsWithDifferentSharesApart() {
    let reset = Date(timeIntervalSince1970: 1_790_000_000)
    var accounts: [UsageAccount] = []
    UsageLimits.merge(claude("~/.claude", used: 40, resetsAt: reset), into: &accounts)
    UsageLimits.merge(claude("~/.claude-work", used: 41, resetsAt: reset), into: &accounts)
    #expect(accounts.count == 2)
}

@Test func mergeNeverFoldsAccountsThatFailed() {
    var accounts: [UsageAccount] = []
    let failed = UsageAccount(provider: "claude", plan: nil, locations: ["~/.claude"], windows: [], error: "x")
    UsageLimits.merge(failed, into: &accounts)
    UsageLimits.merge(UsageAccount(provider: "claude", plan: nil, locations: ["~/.claude-b"], windows: [], error: "x"),
                      into: &accounts)
    #expect(accounts.count == 2)
}
