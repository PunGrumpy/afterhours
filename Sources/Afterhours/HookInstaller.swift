import Foundation
import AfterhoursCore

/// Installs Afterhours's lifecycle hooks into Claude Code `settings.json` files.
enum ClaudeHooks {
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PreCompact", "Notification", "Stop", "SessionEnd",
    ]
    private static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse"]
    private static let marker = "Afterhours/bin/afterhours-hook"

    static var command: String { "'\(AfterhoursPaths.hookBinary.path)' claude" }

    /// `~/.claude` plus any `~/.claude-*` profile directories (CLAUDE_CONFIG_DIR setups).
    static func configDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            dirs.append(URL(fileURLWithPath: (env as NSString).expandingTildeInPath))
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        for name in names.sorted() where name == ".claude" || name.hasPrefix(".claude-") {
            var isDir: ObjCBool = false
            let url = home.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                dirs.append(url)
            }
        }
        var seen: Set<String> = []
        return dirs.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func isInstalled(in dir: URL) -> Bool {
        guard let hooks = readSettings(dir)["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains(where: isOurs)
        }
    }

    static func install(in dir: URL) throws {
        try installHookBinary()
        var settings = readSettings(dir)
        var hooks = stripOurs(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        settings["hooks"] = hooks
        try writeSettings(settings, to: dir)
    }

    static func uninstall(in dir: URL) throws {
        var settings = readSettings(dir)
        let hooks = stripOurs(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(settings, to: dir)
    }

    /// Copies the bundled hook binary to a stable path so hooks survive the app being moved.
    static func installHookBinary() throws {
        guard let bundled = Bundle.main.url(forAuxiliaryExecutable: "afterhours-hook") else {
            throw NSError(domain: "Afterhours", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "afterhours-hook is missing from the app bundle",
            ])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: AfterhoursPaths.bin, withIntermediateDirectories: true)
        let tmp = AfterhoursPaths.bin.appendingPathComponent("afterhours-hook.new")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: bundled, to: tmp)
        try? fm.removeItem(at: AfterhoursPaths.hookBinary)
        try fm.moveItem(at: tmp, to: AfterhoursPaths.hookBinary)
    }

    // MARK: - settings.json

    private static func settingsURL(_ dir: URL) -> URL { dir.appendingPathComponent("settings.json") }

    private static func readSettings(_ dir: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL(dir)) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func writeSettings(_ settings: [String: Any], to dir: URL) throws {
        let url = settingsURL(dir)
        let backup = dir.appendingPathComponent("settings.json.afterhours-backup")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func stripOurs(_ hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            result[event] = kept.isEmpty ? nil : kept
        }
        return result
    }
}
