import Foundation
import AfterhoursCore

// afterhours-hook <agent>  reads a Claude Code hook payload on stdin
// afterhours-hook <agent> --state working|waiting|idle|end [--session <id>]
//
// Always exits 0 and prints nothing, so a failure never breaks the agent.

let args = CommandLine.arguments.dropFirst()
let agent = args.first ?? "agent"

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), args.index(after: i) < args.endIndex else { return nil }
    return args[args.index(after: i)]
}

let payload: [String: Any] = {
    guard option("--state") == nil else { return [:] }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}()

let resolved: HookAction
if let explicit = option("--state") {
    guard let action = HookAction(explicitState: explicit) else { exit(0) }
    resolved = action
} else if let event = payload["hook_event_name"] as? String, let mapped = HookAction(claudeEvent: event) {
    resolved = mapped
} else {
    exit(0)
}

/// The first ancestor that isn't a shell wrapper.
func agentPid() -> Int32? {
    let wrappers: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "afterhours-hook", "timeout"]
    var pid = getppid()
    for _ in 0..<8 {
        guard pid > 1, let name = Proc.name(pid) else { return nil }
        if !wrappers.contains(name) { return pid }
        guard let parent = Proc.parent(pid) else { return nil }
        pid = parent
    }
    return nil
}

let pid = agentPid()
let sessionId = option("--session")
    ?? (payload["session_id"] as? String)
    ?? pid.map(String.init)
    ?? "default"
let file = AfterhoursPaths.sessionFile(agent: agent, id: sessionId)

guard case .set(let newState) = resolved else {
    try? FileManager.default.removeItem(at: file)
    exit(0)
}

let record = SessionRecord(
    id: sessionId,
    agent: agent,
    state: newState,
    pid: pid,
    cwd: payload["cwd"] as? String ?? FileManager.default.currentDirectoryPath,
    updatedAt: Date()
)

try? FileManager.default.createDirectory(at: AfterhoursPaths.sessions, withIntermediateDirectories: true)
if let data = try? JSONEncoder.afterhours.encode(record) {
    try? data.write(to: file, options: .atomic)
}
exit(0)
