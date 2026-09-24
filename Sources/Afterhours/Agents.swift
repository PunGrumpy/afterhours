import Foundation
import AfterhoursCore

/// A coding agent we know how to spot in the process table.
nonisolated struct AgentKind: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Exact process names that identify the agent.
    let processNames: Set<String>
    /// For agents running under an interpreter (node, python, bun): substrings to look for in argv.
    let argvMarkers: [String]
    /// Whether the agent reports state through lifecycle hooks we can install.
    let supportsHooks: Bool

    static let all: [AgentKind] = [
        AgentKind(id: "claude", displayName: "Claude Code", processNames: ["claude"],
                  argvMarkers: ["@anthropic-ai/claude-code", "claude-code/cli"], supportsHooks: true),
        AgentKind(id: "codex", displayName: "Codex", processNames: ["codex"],
                  argvMarkers: ["@openai/codex"], supportsHooks: false),
        AgentKind(id: "opencode", displayName: "OpenCode", processNames: ["opencode"],
                  argvMarkers: ["opencode-ai"], supportsHooks: false),
        // Antigravity CLI replaced Gemini CLI for personal accounts on 2026-06-18.
        // `agy` in a terminal; T3 Code runs it through its ACP server instead.
        AgentKind(id: "antigravity", displayName: "Antigravity CLI", processNames: ["agy", "agy_acp_server.par"],
                  argvMarkers: [], supportsHooks: false),
        // Still served to Gemini Code Assist Standard/Enterprise and Google Cloud users.
        AgentKind(id: "gemini", displayName: "Gemini CLI", processNames: ["gemini"],
                  argvMarkers: ["@google/gemini-cli", "/bin/gemini"], supportsHooks: false),
        AgentKind(id: "copilot", displayName: "Copilot CLI", processNames: ["copilot"],
                  argvMarkers: ["@github/copilot"], supportsHooks: false),
        AgentKind(id: "cursor", displayName: "Cursor CLI", processNames: ["cursor-agent"],
                  argvMarkers: ["cursor-agent"], supportsHooks: false),
        AgentKind(id: "aider", displayName: "Aider", processNames: ["aider"],
                  argvMarkers: ["/bin/aider", "aider/main.py", "-m aider"], supportsHooks: false),
        AgentKind(id: "amp", displayName: "Amp", processNames: ["amp"],
                  argvMarkers: ["@sourcegraph/amp"], supportsHooks: false),
    ]

    static func named(_ id: String) -> AgentKind? { all.first { $0.id == id } }

    /// Looks for agent CLIs in the login shell's PATH plus the usual install locations.
    /// Spawning the login shell takes ~100 ms, so this runs off the main actor.
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
        let cwd: String?
        let lastActive: Date?
    }

    /// Fraction of one core (averaged over a sample interval) that counts as activity.
    var cpuThreshold = 0.03

    private var lastScan: Date?
    private var cpuByPid: [Int32: UInt64] = [:]
    private var lastActive: [Int32: Date] = [:]

    /// One pass over the process table. Returns every running agent root process with its last active time.
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
            // Skip agents whose parent is the same agent (e.g. a node wrapper spawning the real binary).
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
            return Detected(pid: pid, kind: kind, cwd: Proc.cwd(pid), lastActive: lastActive[pid])
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
