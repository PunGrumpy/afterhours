import Foundation

public enum AgentState: String, Codable, Sendable {
    case working
    case waiting  // on a permission prompt or a question for you
    case idle
}

/// How many sessions are in each state, and the words the menu uses for them, so every number it shows counts sessions.
public struct SessionTally: Sendable, Equatable {
    public let working: Int
    public let waiting: Int
    public let idle: Int

    public var total: Int { working + waiting + idle }

    public init(_ states: [AgentState]) {
        working = states.filter { $0 == .working }.count
        waiting = states.filter { $0 == .waiting }.count
        idle = states.filter { $0 == .idle }.count
    }

    /// The summary for the whole Agents section, leading with the sessions that need you.
    public var sectionStatus: String {
        if total == 0 { return "No sessions" }
        let sessions = "\(total) \(total == 1 ? "session" : "sessions")"
        if waiting > 0 {
            let needs = "\(waiting) \(waiting == 1 ? "needs" : "need") you"
            return working > 0 ? "\(needs) · \(working) working" : "\(needs) · \(sessions) open"
        }
        if working == 0 { return "\(sessions) open" }
        return "\(working) of \(sessions) working"
    }

    /// One agent's row, in the order a glance needs them, leaving out what is zero.
    public var rowStatus: [String] {
        [(working, "working"), (waiting, waiting == 1 ? "needs you" : "need you"), (idle, "idle")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
    }
}

/// What a hook event means for the session that sent it.
public enum HookAction: Equatable, Sendable {
    case set(AgentState)
    case end

    /// The Claude Code notification types that mean a person is needed; others, like `idle_prompt`, only say a session went quiet.
    private static let notificationsThatNeedYou: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "worker_permission_prompt", "agent_needs_input",
    ]

    /// Claude Code event names. Unknown events and notifications map to nil so the hook stays quiet.
    public init?(claudeEvent event: String, notificationType: String? = nil) {
        switch event {
        case "SessionStart", "Stop": self = .set(.idle)
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact": self = .set(.working)
        case "PermissionRequest": self = .set(.waiting)
        case "Notification":
            // Older Claude Code sends no type, so the event alone decides.
            guard notificationType.map(Self.notificationsThatNeedYou.contains) ?? true else { return nil }
            self = .set(.waiting)
        case "SessionEnd": self = .end
        default: return nil
        }
    }

    /// The `--state` flag of `afterhours-hook`: `working`, `waiting`, `idle`, or `end`. Anything else is nil.
    public init?(explicitState state: String) {
        if state == "end" { self = .end; return }
        guard let agentState = AgentState(rawValue: state) else { return nil }
        self = .set(agentState)
    }
}

/// One hooked agent session, persisted as a JSON file that the hook writes and the app reads.
public struct SessionRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var agent: String
    public var state: AgentState
    public var pid: Int32?
    public var cwd: String?
    public var updatedAt: Date

    public init(id: String, agent: String, state: AgentState, pid: Int32?, cwd: String?, updatedAt: Date) {
        self.id = id
        self.agent = agent
        self.state = state
        self.pid = pid
        self.cwd = cwd
        self.updatedAt = updatedAt
    }
}

public enum AfterhoursPaths {
    public static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Afterhours", isDirectory: true)
    }

    public static var sessions: URL { support.appendingPathComponent("sessions", isDirectory: true) }
    public static var bin: URL { support.appendingPathComponent("bin", isDirectory: true) }
    public static var usage: URL { support.appendingPathComponent("usage.json") }
    public static var hookBinary: URL { bin.appendingPathComponent("afterhours-hook") }

    /// Replaces characters that aren't safe in a file name.
    public static func sessionFile(agent: String, id: String) -> URL {
        let safe = "\(agent)-\(id)".map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return sessions.appendingPathComponent(String(safe) + ".json")
    }
}

public extension JSONEncoder {
    static let afterhours: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

public extension JSONDecoder {
    static let afterhours: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
