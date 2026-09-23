import Foundation

/// State an agent reports through its lifecycle hooks.
public enum AgentState: String, Codable, Sendable {
    case working
    case waiting  // blocked on the user (permission prompt, question)
    case idle
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
    public static var hookBinary: URL { bin.appendingPathComponent("afterhours-hook") }

    /// File name for a session; hashed-ish so arbitrary ids are safe on disk.
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
