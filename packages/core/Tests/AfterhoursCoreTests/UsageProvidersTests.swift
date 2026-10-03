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
