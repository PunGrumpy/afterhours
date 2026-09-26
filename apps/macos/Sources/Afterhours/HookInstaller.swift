import Foundation
import AfterhoursCore

enum ClaudeHooks {
    static var command: String { "'\(AfterhoursPaths.hookBinary.path)' claude" }

    /// `~/.claude` plus any `~/.claude-*` profiles used with CLAUDE_CONFIG_DIR.
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

    static func isInstalled(in dir: URL) -> Bool { ClaudeHookSettings.isInstalled(in: dir) }

    static func install(in dir: URL) throws {
        try installHookBinary()
        try ClaudeHookSettings.install(in: dir, command: command)
    }

    static func uninstall(in dir: URL) throws { try ClaudeHookSettings.uninstall(in: dir) }

    /// A stable path keeps hooks working after the app moves.
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
        // One rename, so a hook firing mid-launch never finds the binary missing.
        if fm.fileExists(atPath: AfterhoursPaths.hookBinary.path) {
            _ = try fm.replaceItemAt(AfterhoursPaths.hookBinary, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: AfterhoursPaths.hookBinary)
        }
    }
}
