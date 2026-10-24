import Foundation
import Testing
@testable import AfterhoursCore

private func runSQLite(_ database: URL, _ sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = ["-init", "/dev/null", database.path, sql]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func cursorStateIsReadWithoutTheUsersSqliteSettings() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("afterhours-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let config = dir.appendingPathComponent("config", isDirectory: true)
    try FileManager.default.createDirectory(at: config.appendingPathComponent("sqlite3", isDirectory: true),
                                            withIntermediateDirectories: true)
    // Settings like these used to turn the token into "value\n-------\n<token>".
    try Data(".headers on\n.mode column\n".utf8).write(to: config.appendingPathComponent("sqlite3/sqliterc"))
    let database = dir.appendingPathComponent("state.vscdb")
    try runSQLite(database, """
        CREATE TABLE ItemTable (key TEXT, value TEXT);
        INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'token-123');
        """)
    let environment = ["XDG_CONFIG_HOME": config.path]
    #expect(UsageLimits.sqliteValue(database: database, key: "cursorAuth/accessToken", environment: environment)
            == "token-123")
    #expect(UsageLimits.sqliteValue(database: database, key: "missing", environment: environment) == nil)
}

// MARK: - Antigravity

private let antigravityFixture = Data("""
    {"groups": [
      {"displayName": "Gemini Models", "buckets": [
        {"bucketId": "gemini-weekly", "window": "weekly", "resetTime": "2026-10-18T13:49:14Z",
         "remainingFraction": 0.75},
        {"bucketId": "gemini-5h", "window": "5h", "resetTime": "2026-10-12T07:09:29Z", "remainingFraction": 1}]},
      {"displayName": "Claude and GPT models", "buckets": [
        {"bucketId": "3p-weekly", "window": "weekly", "resetTime": "2026-10-19T02:09:29Z", "remainingFraction": 0},
        {"bucketId": "3p-unreported", "window": "weekly", "resetTime": "2026-10-19T02:09:29Z"},
        {"bucketId": "3p-5h", "window": "5h", "remainingFraction": 0.5, "disabled": true},
        {"bucketId": "3p-daily", "window": "24h", "remainingFraction": 0.5}]}
    ]}
    """.utf8)

@Test func antigravityAccountReadsEachGroupsWindows() throws {
    let account = try #require(UsageLimits.antigravityAccount(.success(antigravityFixture), plan: "Google AI Pro",
                                                              locations: ["a@b.c"]))
    #expect(account.windows.map(\.id) == ["gemini-weekly", "gemini-5h", "3p-weekly"])
    #expect(account.windows.map(\.kind) == [.weekly, .session, .weekly])
    #expect(account.windows.map(\.label) == ["Weekly · Gemini", "Session · Gemini", "Weekly · Claude & GPT"])
    #expect(account.windows.map(\.usedPercent) == [25, 0, 100])
    #expect(account.windows[0].resetsAt == Date(timeIntervalSince1970: 1_792_331_354))
}

@Test func antigravityAccountIsHiddenWithoutAnAllowance() {
    #expect(UsageLimits.antigravityAccount(.success(Data("{}".utf8)), plan: nil, locations: ["a@b.c"]) == nil)
}

@Test func antigravityAccountAsksForSignInWhenRejected() {
    let account = UsageLimits.antigravityAccount(.failure(.status(401)), plan: nil, locations: ["T3 Code"])
    #expect(account?.windows.isEmpty == true)
    #expect(account?.error == "Sign in to Antigravity again")
}

@Test func antigravityLoginsCoverTheGeminiHomeAndT3CodeProfiles() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("afterhours-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let profiles = home.appendingPathComponent(".t3/userdata/providers/antigravity")
    for dir in [home.appendingPathComponent(".gemini"), profiles.appendingPathComponent("b"),
                profiles.appendingPathComponent("a"), profiles.appendingPathComponent("signed-out")] {
        let acp = dir.appendingPathComponent("antigravity-acp", isDirectory: true)
        try FileManager.default.createDirectory(at: acp, withIntermediateDirectories: true)
        if dir.lastPathComponent != "signed-out" {
            try Data("{}".utf8).write(to: acp.appendingPathComponent("acp_token.json"))
        }
    }
    let logins = UsageLimits.antigravityLogins(home: home)
    #expect(logins.map(\.file.path) == [".gemini", ".t3/userdata/providers/antigravity/a",
                                        ".t3/userdata/providers/antigravity/b"]
        .map { home.appendingPathComponent("\($0)/antigravity-acp/acp_token.json").path })
    #expect(logins.map(\.location).dropFirst() == ["T3 Code", "T3 Code"])
}

@Test func antigravityStopsAtTheFirstHostThatRejectsTheToken() {
    #expect(!UsageLimits.antigravityTriesNextHost(after: .success(Data())))
    #expect(!UsageLimits.antigravityTriesNextHost(after: .failure(.status(401))))
    #expect(UsageLimits.antigravityTriesNextHost(after: .failure(.status(403))))
    #expect(UsageLimits.antigravityTriesNextHost(after: .failure(.status(503))))
    #expect(UsageLimits.antigravityTriesNextHost(after: .failure(.network("offline"))))
    #expect(UsageLimits.antigravityTriesNextHost(after: .failure(.decoding)))
}

@Test func antigravityRowKeepsItsEmailWhenTheExchangeFails() {
    #expect(UsageLimits.antigravityLocation(email: "a@b.c", knownEmail: nil, fallback: "T3 Code") == "a@b.c")
    #expect(UsageLimits.antigravityLocation(email: nil, knownEmail: "a@b.c", fallback: "T3 Code") == "a@b.c")
    #expect(UsageLimits.antigravityLocation(email: nil, knownEmail: nil, fallback: "T3 Code") == "T3 Code")
}

private let openCodeFixture = Data("""
    {"usage": {
      "rolling": {"percent": 12.5, "resetsAt": "2026-10-18T13:49:14Z"},
      "weekly": {"percent": 40},
      "monthly": {"percent": 0, "resetsAt": "2026-11-01T00:00:00Z"}}}
    """.utf8)

@Test func openCodeAccountReadsEachWindow() throws {
    let account = try #require(UsageLimits.openCodeAccount(.success(openCodeFixture),
                                                           locations: ["~/.local/share/opencode"]))
    #expect(account.plan == "Go")
    #expect(account.windows.map(\.id) == ["rolling", "weekly", "monthly"])
    #expect(account.windows.map(\.kind) == [.session, .weekly, .monthly])
    #expect(account.windows.map(\.usedPercent) == [12.5, 40, 0])
    #expect(account.windows[0].resetsAt == Date(timeIntervalSince1970: 1_792_331_354))
    #expect(account.windows[1].resetsAt == nil)
    #expect(account.error == nil)
}

@Test func openCodeAccountDropsAWindowWithoutAPercent() throws {
    let body = Data(#"{"usage": {"rolling": {"resetsAt": "2026-10-18T13:49:14Z"}, "weekly": {"percent": 40}}}"#.utf8)
    let account = try #require(UsageLimits.openCodeAccount(.success(body), locations: []))
    #expect(account.windows.map(\.id) == ["weekly"])
}

@Test func openCodeAccountIsHiddenWhenOnlyZenIsSignedIn() {
    #expect(UsageLimits.openCodeAccount(.failure(.status(403)), locations: []) == nil)
}

@Test func openCodeAccountAsksForSignInWhenRejected() {
    let account = UsageLimits.openCodeAccount(.failure(.status(401)), locations: ["~/.local/share/opencode"])
    #expect(account?.windows.isEmpty == true)
    #expect(account?.error == "Run opencode once to refresh its login")
}

@Test func openCodeAccountReportsAnUnreadableBody() {
    let account = UsageLimits.openCodeAccount(.success(Data("{".utf8)), locations: [])
    #expect(account?.windows.isEmpty == true)
    #expect(account?.error == "Couldn't read the usage response")
}
