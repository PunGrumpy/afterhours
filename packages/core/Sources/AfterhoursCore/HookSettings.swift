import Foundation

/// Edits the `hooks` block of a Claude Code `settings.json` without touching anything else in it.
public enum ClaudeHookSettings {
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PreCompact", "Notification", "Stop", "SessionEnd",
    ]
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse"]
    /// Identifies our entries whatever the install path was.
    public static let marker = "Afterhours/bin/afterhours-hook"
    public static let backupName = "settings.json.afterhours-backup"

    public struct UnreadableSettings: Error, LocalizedError {
        public let path: String
        public var errorDescription: String? {
            "\(path) isn't valid JSON. Fix it, or restore it from \(backupName), then try again."
        }
    }

    public static func isInstalled(in dir: URL) -> Bool {
        guard let settings = try? read(dir), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains(where: isOurs)
        }
    }

    /// Adds our hook to every event, replacing any earlier copy of ours and keeping everyone else's.
    public static func install(in dir: URL, command: String) throws {
        var settings = try read(dir)
        var hooks = stripOurs(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        settings["hooks"] = hooks
        try write(settings, to: dir)
    }

    public static func uninstall(in dir: URL) throws {
        var settings = try read(dir)
        let hooks = stripOurs(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try write(settings, to: dir)
    }

    static func settingsURL(_ dir: URL) -> URL { dir.appendingPathComponent("settings.json") }

    /// A missing file is empty settings; a file that exists but won't parse is an error, since writing
    /// over it would throw away whatever the user had.
    static func read(_ dir: URL) throws -> [String: Any] {
        let url = settingsURL(dir)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UnreadableSettings(path: url.path)
        }
        return object
    }

    static func write(_ settings: [String: Any], to dir: URL) throws {
        let fm = FileManager.default
        // Resolve the symlink first, so a dotfile-managed settings.json stays a symlink.
        let url = settingsURL(dir).resolvingSymlinksInPath()
        let backup = dir.appendingPathComponent(backupName)
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    static func stripOurs(_ hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            result[event] = kept.isEmpty ? nil : kept
        }
        return result
    }
}
