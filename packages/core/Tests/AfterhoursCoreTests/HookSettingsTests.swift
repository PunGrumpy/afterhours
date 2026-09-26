import Foundation
import Testing
@testable import AfterhoursCore

private let command = "'/Users/me/Library/Application Support/Afterhours/bin/afterhours-hook' claude"

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("afterhours-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeSettings(_ text: String, in dir: URL) throws {
    try Data(text.utf8).write(to: dir.appendingPathComponent("settings.json"))
}

private func readSettings(in dir: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let existing = """
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo hi"}]}]
  }
}
"""

@Test func installKeepsEveryoneElsesSettingsAndHooks() throws {
    let dir = try tempDir()
    try writeSettings(existing, in: dir)
    try ClaudeHookSettings.install(in: dir, command: command)
    let settings = try readSettings(in: dir)
    #expect((settings["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
    let hooks = try #require(settings["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 2)
    #expect(((stop[0]["hooks"] as? [[String: Any]])?[0]["command"] as? String) == "say done")
    let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(preToolUse.count == 2)
    #expect(preToolUse[1]["matcher"] as? String == "*")
    #expect(ClaudeHookSettings.isInstalled(in: dir))
    #expect(Set(hooks.keys).isSuperset(of: ClaudeHookSettings.events))
}

@Test func installingTwiceDoesNotDuplicateOurHooks() throws {
    let dir = try tempDir()
    try writeSettings(existing, in: dir)
    try ClaudeHookSettings.install(in: dir, command: command)
    try ClaudeHookSettings.install(in: dir, command: command)
    let hooks = try #require(try readSettings(in: dir)["hooks"] as? [String: Any])
    #expect((hooks["Stop"] as? [[String: Any]])?.count == 2)
    #expect((hooks["SessionEnd"] as? [[String: Any]])?.count == 1)
}

@Test func uninstallRemovesOnlyOurHooksAndDropsAnEmptyBlock() throws {
    let dir = try tempDir()
    try writeSettings(existing, in: dir)
    try ClaudeHookSettings.install(in: dir, command: command)
    try ClaudeHookSettings.uninstall(in: dir)
    let settings = try readSettings(in: dir)
    let hooks = try #require(settings["hooks"] as? [String: Any])
    #expect(Set(hooks.keys) == ["Stop", "PreToolUse"])
    #expect(!ClaudeHookSettings.isInstalled(in: dir))

    let empty = try tempDir()
    try ClaudeHookSettings.install(in: empty, command: command)
    try ClaudeHookSettings.uninstall(in: empty)
    #expect(try readSettings(in: empty)["hooks"] == nil)
}

@Test func installStartsFromAnEmptyObjectWhenThereIsNoFile() throws {
    let dir = try tempDir()
    try ClaudeHookSettings.install(in: dir, command: command)
    #expect(ClaudeHookSettings.isInstalled(in: dir))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(ClaudeHookSettings.backupName).path))
}

@Test func installRefusesToRewriteAFileThatWontParse() throws {
    let dir = try tempDir()
    let broken = "{ \"permissions\": { \"allow\": [\"Bash(ls:*)\"] }"
    try writeSettings(broken, in: dir)
    #expect(throws: ClaudeHookSettings.UnreadableSettings.self) {
        try ClaudeHookSettings.install(in: dir, command: command)
    }
    #expect(throws: ClaudeHookSettings.UnreadableSettings.self) {
        try ClaudeHookSettings.uninstall(in: dir)
    }
    let after = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(after == broken)
    #expect(!ClaudeHookSettings.isInstalled(in: dir))
}

@Test func everyWriteRefreshesTheBackup() throws {
    let dir = try tempDir()
    try writeSettings(existing, in: dir)
    try ClaudeHookSettings.install(in: dir, command: command)
    let backup = dir.appendingPathComponent(ClaudeHookSettings.backupName)
    let first = try String(contentsOf: backup, encoding: .utf8)
    #expect(first == existing)
    try ClaudeHookSettings.uninstall(in: dir)
    let second = try String(contentsOf: backup, encoding: .utf8)
    #expect(second.contains(ClaudeHookSettings.marker))
}

@Test func writesGoThroughASymlinkInsteadOfReplacingIt() throws {
    let dir = try tempDir()
    let target = dir.appendingPathComponent("real-settings.json")
    try Data(existing.utf8).write(to: target)
    let link = dir.appendingPathComponent("settings.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    try ClaudeHookSettings.install(in: dir, command: command)
    let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
    #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
    let written = try String(contentsOf: target, encoding: .utf8)
    #expect(written.contains(ClaudeHookSettings.marker))
}
