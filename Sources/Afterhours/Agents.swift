import Foundation
import AfterhoursCore

nonisolated struct AgentKind: Identifiable, Hashable {
    let id: String
    let displayName: String
    let processNames: Set<String>
    /// Substrings to look for in argv when the agent runs under node, bun, or python.
    let argvMarkers: [String]

    static let all: [AgentKind] = [
        AgentKind(id: "claude", displayName: "Claude Code", processNames: ["claude"],
                  argvMarkers: ["@anthropic-ai/claude-code", "claude-code/cli"]),
        AgentKind(id: "codex", displayName: "Codex", processNames: ["codex"], argvMarkers: ["@openai/codex"]),
        AgentKind(id: "opencode", displayName: "OpenCode", processNames: ["opencode"], argvMarkers: ["opencode-ai"]),
        // Replaced Gemini CLI on 2026-06-18. T3 Code runs it through its ACP server instead of `agy`.
        AgentKind(id: "antigravity", displayName: "Antigravity CLI", processNames: ["agy", "agy_acp_server.par"],
                  argvMarkers: []),
        // Still served to Gemini Code Assist and Google Cloud users.
        AgentKind(id: "gemini", displayName: "Gemini CLI", processNames: ["gemini"],
                  argvMarkers: ["@google/gemini-cli", "/bin/gemini"]),
        AgentKind(id: "copilot", displayName: "Copilot CLI", processNames: ["copilot"], argvMarkers: ["@github/copilot"]),
        AgentKind(id: "cursor", displayName: "Cursor CLI", processNames: ["cursor-agent"], argvMarkers: ["cursor-agent"]),
        AgentKind(id: "aider", displayName: "Aider", processNames: ["aider"],
                  argvMarkers: ["/bin/aider", "aider/main.py", "-m aider"]),
        AgentKind(id: "amp", displayName: "Amp", processNames: ["amp"], argvMarkers: ["@sourcegraph/amp"]),
    ]

    static func named(_ id: String) -> AgentKind? { all.first { $0.id == id } }

    /// Looks for agent CLIs on the login shell's PATH and in common install directories.
    @concurrent static func findInstalled() async -> Set<String> {
        let home = NSHomeDirectory()
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/homebrew/bin", "\(home)/.local/bin",
                    "\(home)/.bun/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin",
                    "\(home)/.opencode/bin", "\(home)/.claude/local", "\(home)/.amp/bin"]
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let path = Power.run(shell, ["-lc", "printf %s \"$PATH\""]).output
        dirs += path.split(separator: ":").map(String.init)
        let fm = FileManager.default
        return Set(all.filter { kind in
            kind.processNames.contains { name in dirs.contains { fm.isExecutableFile(atPath: "\($0)/\(name)") } }
        }.map(\.id))
    }

    static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "Python"]
}

/// Tracks CPU usage of agent process trees so we can tell "working" from "sitting at a prompt".
struct ActivityTracker {
    struct Detected {
        let pid: Int32
        let kind: AgentKind
        let lastActive: Date?
    }

    /// Fraction of one core, averaged between scans, that counts as activity.
    private let cpuThreshold = 0.03

    private var lastScan: Date?
    private var cpuByPid: [Int32: UInt64] = [:]
    private var lastActive: [Int32: Date] = [:]

    mutating func scan(enabled: Set<String>) -> [Detected] {
        let now = Date()
        let pids = Proc.allPids()
        var children: [Int32: [Int32]] = [:]
        var names: [Int32: String] = [:]
        for pid in pids {
            if let parent = Proc.parent(pid) { children[parent, default: []].append(pid) }
            if let name = Proc.name(pid) { names[pid] = name }
        }

        var roots: [(Int32, AgentKind)] = []
        for (pid, name) in names {
            guard let kind = match(pid: pid, name: name, enabled: enabled) else { continue }
            // A node wrapper that spawns the real binary would otherwise count twice.
            if let parent = Proc.parent(pid), let parentName = names[parent],
               match(pid: parent, name: parentName, enabled: enabled)?.id == kind.id {
                continue
            }
            roots.append((pid, kind))
        }

        // The first scan (elapsed == 0) only establishes a CPU baseline.
        let elapsed = lastScan.map { now.timeIntervalSince($0) } ?? 0
        var nextCPU: [Int32: UInt64] = [:]
        let results = roots.map { pid, kind -> Detected in
            var busyNanos: UInt64 = 0
            for member in tree(pid, children: children) {
                guard let cpu = Proc.cpuNanos(member) else { continue }
                nextCPU[member] = cpu
                // A pid we haven't seen was spawned since the last scan, so all of its CPU is new.
                let before = cpuByPid[member] ?? 0
                if cpu > before { busyNanos += cpu - before }
            }
            if elapsed > 0, Double(busyNanos) / 1e9 / elapsed >= cpuThreshold {
                lastActive[pid] = now
            }
            return Detected(pid: pid, kind: kind, lastActive: lastActive[pid])
        }

        lastScan = now
        cpuByPid = nextCPU
        let live = Set(roots.map(\.0))
        lastActive = lastActive.filter { live.contains($0.key) }
        return results
    }

    private func match(pid: Int32, name: String, enabled: Set<String>) -> AgentKind? {
        let candidates = AgentKind.all.filter { enabled.contains($0.id) }
        if let kind = candidates.first(where: { $0.processNames.contains(name) }) { return kind }
        guard AgentKind.interpreters.contains(name) else { return nil }
        let argv = Proc.arguments(pid).prefix(4).joined(separator: " ")
        return candidates.first { kind in kind.argvMarkers.contains { argv.contains($0) } }
    }

    private func tree(_ root: Int32, children: [Int32: [Int32]]) -> Set<Int32> {
        var visited: Set<Int32> = []
        var stack = [root]
        while let pid = stack.popLast() {
            guard visited.insert(pid).inserted else { continue }
            stack.append(contentsOf: children[pid] ?? [])
        }
        return visited
    }
}
