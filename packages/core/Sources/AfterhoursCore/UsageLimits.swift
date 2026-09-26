import CryptoKit
import Foundation

/// One rate-limit window of a subscription, as a share used.
public struct UsageWindow: Sendable, Identifiable, Equatable {
    public enum Kind: Int, Sendable, Comparable {
        case session, weekly, monthly

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let id: String
    public let kind: Kind
    public let label: String
    /// 0 to 100.
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, kind: Kind, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent.isFinite ? usedPercent : 0))
        self.resetsAt = resetsAt
    }
}

/// A signed-in subscription account and what it reported.
public struct UsageAccount: Sendable, Identifiable, Equatable {
    /// An agent id from `AgentKind`, like "claude" or "codex".
    public let provider: String
    public let plan: String?
    /// Where the login lives, like "~/.claude-work", so two accounts of one provider tell apart.
    public var locations: [String]
    public let windows: [UsageWindow]
    /// Why nothing could be read, shown instead of the windows.
    public let error: String?

    public var id: String { "\(provider):\(locations.joined(separator: ","))" }

    public init(provider: String, plan: String?, locations: [String], windows: [UsageWindow], error: String? = nil) {
        self.provider = provider
        self.plan = plan
        self.locations = locations
        self.windows = windows
        self.error = error
    }
}

/// Reads subscription quotas the way the CLIs do, with the logins they already keep on this Mac.
/// Read-only: it never refreshes a token, so an expired login asks you to run the CLI once.
public enum UsageLimits {
    static let timeout: TimeInterval = 10

    /// Every account found, one per login. Claude logins that report identical reset times are one account.
    @concurrent
    public static func read(claudeConfigDirectories: [URL], codexHome: URL? = nil) async -> [UsageAccount] {
        async let claude = readClaude(configDirectories: claudeConfigDirectories)
        async let codex = readCodex(home: codexHome ?? defaultCodexHome)
        var accounts = await claude
        if let codex = await codex { accounts.append(codex) }
        return accounts
    }

    // MARK: - Claude Code

    private struct ClaudeCredentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
            let subscriptionType: String?
        }

        let claudeAiOauth: OAuth?
    }

    private struct ClaudeUsage: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?
        }

        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let displayName: String? }
                let model: Model?
            }

            let kind: String?
            let percent: Double?
            let resetsAt: String?
            let scope: Scope?
        }

        let fiveHour: Window?
        let sevenDay: Window?
        let limits: [Limit]?
    }

    static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static func readClaude(configDirectories: [URL]) async -> [UsageAccount] {
        var accounts: [UsageAccount] = []
        for dir in configDirectories {
            guard let credentials = claudeCredentials(in: dir),
                  let token = credentials.claudeAiOauth?.accessToken, !token.isEmpty
            else { continue }
            let location = shortPath(dir)
            let plan = credentials.claudeAiOauth?.subscriptionType.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            var request = URLRequest(url: claudeUsageURL, timeoutInterval: timeout)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            let account: UsageAccount
            switch await fetch(request, as: ClaudeUsage.self) {
            case .success(let usage):
                account = UsageAccount(provider: "claude", plan: plan, locations: [location],
                                       windows: claudeWindows(usage))
            case .failure(let error):
                account = UsageAccount(provider: "claude", plan: plan, locations: [location], windows: [],
                                       error: error.message(signIn: "Run claude once to refresh its login"))
            }
            if let index = accounts.firstIndex(where: { sameAccount($0, account) }) {
                accounts[index].locations.append(location)
            } else {
                accounts.append(account)
            }
        }
        return accounts
    }

    /// The usage response names no account, but two logins to one report the same shares and reset
    /// minutes, and two accounts practically never do. Sub-second parts of a reset time vary per call.
    private static func sameAccount(_ a: UsageAccount, _ b: UsageAccount) -> Bool {
        guard a.error == nil, b.error == nil, !a.windows.isEmpty else { return false }
        func key(_ window: UsageWindow) -> (String, Double, Int?) {
            (window.id, window.usedPercent, window.resetsAt.map { Int(($0.timeIntervalSince1970 / 60).rounded()) })
        }
        return a.windows.count == b.windows.count && zip(a.windows, b.windows).allSatisfy { key($0) == key($1) }
    }

    private static func claudeWindows(_ usage: ClaudeUsage) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        if let percent = usage.fiveHour?.utilization {
            windows.append(UsageWindow(id: "five_hour", kind: .session, label: "Session", usedPercent: percent,
                                       resetsAt: usage.fiveHour?.resetsAt.flatMap(parseISO8601)))
        }
        if let percent = usage.sevenDay?.utilization {
            windows.append(UsageWindow(id: "seven_day", kind: .weekly, label: "Weekly", usedPercent: percent,
                                       resetsAt: usage.sevenDay?.resetsAt.flatMap(parseISO8601)))
        }
        for limit in usage.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let name = limit.scope?.model?.displayName, let percent = limit.percent else { continue }
            windows.append(UsageWindow(id: "seven_day_\(name.lowercased())", kind: .weekly, label: "Weekly · \(name)",
                                       usedPercent: percent, resetsAt: limit.resetsAt.flatMap(parseISO8601)))
        }
        return windows
    }

    /// Claude Code keeps its login in the Keychain on macOS, under a service named after the config dir.
    /// The `security` tool created the item, so it may read it back without a permission prompt.
    private static func claudeCredentials(in dir: URL) -> ClaudeCredentials? {
        let path = dir.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var services = ["Claude Code-credentials-\(sha256Prefix(path))"]
        if path == "\(home)/.claude" { services.insert("Claude Code-credentials", at: 0) }
        for service in services {
            if let data = keychainPassword(service: service),
               let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) {
                return credentials
            }
        }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(".credentials.json")) else { return nil }
        return try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
    }

    private static func keychainPassword(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    private static func sha256Prefix(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Codex

    private struct CodexAuth: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?
            let idToken: String?
        }

        let tokens: Tokens?
    }

    private struct CodexUsage: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Double?
            let resetAt: Double?
        }

        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }

        let planType: String?
        let rateLimit: RateLimit?
    }

    static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static var defaultCodexHome: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private static func readCodex(home: URL) async -> UsageAccount? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let auth = try? snakeCaseDecoder.decode(CodexAuth.self, from: data),
              let token = auth.tokens?.accessToken, !token.isEmpty
        else { return nil }
        let location = shortPath(home)
        var request = URLRequest(url: codexUsageURL, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let accountId = auth.tokens?.accountId ?? auth.tokens?.idToken.flatMap(chatGPTAccountId) {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        switch await fetch(request, as: CodexUsage.self) {
        case .success(let usage):
            let plan = usage.planType.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return UsageAccount(provider: "codex", plan: plan, locations: [location], windows: codexWindows(usage))
        case .failure(let error):
            return UsageAccount(provider: "codex", plan: nil, locations: [location], windows: [],
                                error: error.message(signIn: "Run codex once to refresh its login"))
        }
    }

    private static func codexWindows(_ usage: CodexUsage) -> [UsageWindow] {
        let week: TimeInterval = 7 * 24 * 3600
        let month: TimeInterval = 30 * 24 * 3600
        let positions: [(String, CodexUsage.Window?, TimeInterval)] = [
            ("primary", usage.rateLimit?.primaryWindow, 5 * 3600),
            ("secondary", usage.rateLimit?.secondaryWindow, week),
        ]
        return positions.compactMap { id, window, fallback in
            guard let window, let percent = window.usedPercent else { return nil }
            let seconds = window.limitWindowSeconds ?? fallback
            let kind: UsageWindow.Kind = seconds >= month ? .monthly : seconds >= week ? .weekly : .session
            let label = switch kind {
            case .session: "Session"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            }
            let resetsAt = window.resetAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            return UsageWindow(id: id, kind: kind, label: label, usedPercent: percent, resetsAt: resetsAt)
        }
    }

    /// The workspace id lives in the id token's `https://api.openai.com/auth` claim.
    private static func chatGPTAccountId(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    // MARK: - Shared

    enum FetchError: Error {
        case network(String)
        case status(Int)
        case decoding

        func message(signIn: String) -> String {
            switch self {
            case .status(401), .status(403): signIn
            case .status(let code): "Usage isn't available right now (HTTP \(code))"
            case .network(let text): text
            case .decoding: "Couldn't read the usage response"
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static let snakeCaseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func fetch<T: Decodable>(_ request: URLRequest, as type: T.Type) async -> Result<T, FetchError> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { return .failure(.status(status)) }
        guard let value = try? snakeCaseDecoder.decode(T.self, from: data) else { return .failure(.decoding) }
        return .success(value)
    }

    /// Anthropic sends fractional seconds; a formatter parses either way but only one form at a time.
    private static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
