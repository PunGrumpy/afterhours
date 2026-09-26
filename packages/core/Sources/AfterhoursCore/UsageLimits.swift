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
    /// How long the window runs, so the burn rate can be projected to its reset.
    public let duration: TimeInterval

    public init(id: String, kind: Kind, label: String, usedPercent: Double, resetsAt: Date?,
                duration: TimeInterval? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent.isFinite ? usedPercent : 0))
        self.resetsAt = resetsAt
        self.duration = duration ?? kind.defaultDuration
    }

    public var leftPercent: Double { 100 - usedPercent }

    /// Where the window is heading at the current burn rate, or nil while it's too young to say.
    public struct Pace: Sendable, Equatable {
        /// Share of the window elapsed, 0 to 1. The even-pace mark sits at `1 - elapsed` on a bar of what's left.
        public let elapsed: Double
        /// What would be left at the reset if the burn rate held; below zero means it runs out first.
        public let projectedLeft: Double
        /// When it runs out at this rate, if before the reset.
        public let runsOutAt: Date?

        public init(elapsed: Double, projectedLeft: Double, runsOutAt: Date?) {
            self.elapsed = elapsed
            self.projectedLeft = projectedLeft
            self.runsOutAt = runsOutAt
        }
    }

    /// Needs a reset time, some use, and at least a twentieth of the window behind it.
    public func pace(now: Date = Date()) -> Pace? {
        guard let resetsAt, usedPercent > 0, duration > 0 else { return nil }
        let elapsed = min(1, max(0, (duration - resetsAt.timeIntervalSince(now)) / duration))
        guard elapsed >= 0.05 else { return nil }
        let projectedUsed = usedPercent / elapsed
        let runsOut = projectedUsed > 100 ? now.addingTimeInterval(leftPercent / usedPercent * elapsed * duration) : nil
        return Pace(elapsed: elapsed, projectedLeft: 100 - projectedUsed, runsOutAt: runsOut)
    }
}

public extension UsageWindow.Kind {
    var defaultDuration: TimeInterval {
        switch self {
        case .session: 5 * 3600
        case .weekly: 7 * 24 * 3600
        case .monthly: 30 * 24 * 3600
        }
    }
}

/// A signed-in subscription account and what it reported.
public struct UsageAccount: Sendable, Identifiable, Equatable {
    /// An agent id from `AgentKind`, like "claude" or "codex".
    public let provider: String
    public let plan: String?
    /// Where the login lives: "~/.claude-work" on this Mac, or the account's email on a hub.
    public var locations: [String]
    /// The hub that holds the login, or nil for a login on this Mac.
    public let source: String?
    public let windows: [UsageWindow]
    /// Why nothing could be read, shown instead of the windows.
    public let error: String?

    public var id: String { "\(source ?? "local"):\(provider):\(locations.joined(separator: ","))" }

    public init(provider: String, plan: String?, locations: [String], source: String? = nil,
                windows: [UsageWindow], error: String? = nil) {
        self.provider = provider
        self.plan = plan
        self.locations = locations
        self.source = source
        self.windows = windows
        self.error = error
    }
}

/// A CLIProxyAPI hub that pools subscription accounts. The management key lives in the Keychain.
public struct UsageHub: Sendable, Codable, Identifiable, Equatable {
    public var id: String
    public var label: String
    public var url: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, label: String, url: String, enabled: Bool = true) {
        self.id = id
        self.label = label
        self.url = url
        self.enabled = enabled
    }

    public static let keychainService = "Afterhours-hub"

    public var managementKey: String? {
        KeychainCLI.read(service: Self.keychainService, account: id).flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func saveManagementKey(_ key: String) -> Bool {
        KeychainCLI.write(service: Self.keychainService, account: id, value: key)
    }

    public func deleteManagementKey() {
        KeychainCLI.delete(service: Self.keychainService, account: id)
    }
}

/// Everything one read found.
public struct UsageSnapshot: Sendable, Equatable {
    public var accounts: [UsageAccount]
    /// Hubs that couldn't be listed, as "label: reason".
    public var hubErrors: [String]

    public init(accounts: [UsageAccount] = [], hubErrors: [String] = []) {
        self.accounts = accounts
        self.hubErrors = hubErrors
    }
}

/// Reads subscription quotas the way the CLIs do, with the logins they already keep on this Mac,
/// plus accounts pooled on CLIProxyAPI hubs. Read-only: it never refreshes a token, so an expired
/// login asks you to run the CLI once.
public enum UsageLimits {
    static let timeout: TimeInterval = 10

    /// Every account found, one per login. Logins that report identical shares are one account.
    @concurrent
    public static func read(claudeConfigDirectories: [URL], codexHome: URL? = nil,
                            hubs: [UsageHub] = []) async -> UsageSnapshot {
        async let claude = readClaude(configDirectories: claudeConfigDirectories)
        async let codex = readCodex(home: codexHome ?? defaultCodexHome)
        async let others = readOtherProviders()
        async let hubbed = readHubs(hubs.filter(\.enabled))
        var snapshot = UsageSnapshot()
        for account in await claude { merge(account, into: &snapshot.accounts) }
        if let codex = await codex { merge(codex, into: &snapshot.accounts) }
        for account in await others { merge(account, into: &snapshot.accounts) }
        let (hubAccounts, hubErrors) = await hubbed
        for account in hubAccounts { merge(account, into: &snapshot.accounts) }
        snapshot.hubErrors = hubErrors
        return snapshot
    }

    private static func merge(_ account: UsageAccount, into accounts: inout [UsageAccount]) {
        if let index = accounts.firstIndex(where: { sameAccount($0, account) }) {
            accounts[index].locations.append(contentsOf: account.locations)
        } else {
            accounts.append(account)
        }
    }

    /// The usage response names no account, but two logins to one report the same shares and reset
    /// minutes, and two accounts practically never do. Sub-second parts of a reset time vary per call.
    private static func sameAccount(_ a: UsageAccount, _ b: UsageAccount) -> Bool {
        guard a.provider == b.provider, a.error == nil, b.error == nil, !a.windows.isEmpty else { return false }
        func key(_ window: UsageWindow) -> (String, Double, Int?) {
            (window.id, window.usedPercent, window.resetsAt.map { Int(($0.timeIntervalSince1970 / 60).rounded()) })
        }
        return a.windows.count == b.windows.count && zip(a.windows, b.windows).allSatisfy { key($0) == key($1) }
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
    static let claudeHeaders = ["anthropic-beta": "oauth-2025-04-20"]

    private static func readClaude(configDirectories: [URL]) async -> [UsageAccount] {
        var accounts: [UsageAccount] = []
        for dir in configDirectories {
            guard let credentials = claudeCredentials(in: dir),
                  let token = credentials.claudeAiOauth?.accessToken, !token.isEmpty
            else { continue }
            let plan = credentials.claudeAiOauth?.subscriptionType.map(capitalized)
            let result = await fetch(claudeUsageURL, token: token, headers: claudeHeaders)
            accounts.append(claudeAccount(result, plan: plan, locations: [shortPath(dir)], source: nil))
        }
        return accounts
    }

    private static func claudeAccount(_ result: Result<Data, FetchError>, plan: String?, locations: [String],
                                      source: String?) -> UsageAccount {
        switch result.flatMap({ decode(ClaudeUsage.self, from: $0) }) {
        case .success(let usage):
            UsageAccount(provider: "claude", plan: plan, locations: locations, source: source,
                         windows: claudeWindows(usage))
        case .failure(let error):
            UsageAccount(provider: "claude", plan: plan, locations: locations, source: source, windows: [],
                         error: error.message(signIn: "Run claude once to refresh its login"))
        }
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
    private static func claudeCredentials(in dir: URL) -> ClaudeCredentials? {
        let path = dir.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var services = ["Claude Code-credentials-\(sha256Prefix(path))"]
        if path == "\(home)/.claude" { services.insert("Claude Code-credentials", at: 0) }
        for service in services {
            if let data = KeychainCLI.read(service: service),
               let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) {
                return credentials
            }
        }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(".credentials.json")) else { return nil }
        return try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
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

    static func codexHeaders(accountId: String?) -> [String: String] {
        var headers = ["User-Agent": "codex-cli", "OpenAI-Beta": "codex-1", "Originator": "Codex Desktop"]
        if let accountId { headers["ChatGPT-Account-Id"] = accountId }
        return headers
    }

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
        let accountId = auth.tokens?.accountId ?? auth.tokens?.idToken.flatMap(chatGPTAccountId)
        let result = await fetch(codexUsageURL, token: token, headers: codexHeaders(accountId: accountId))
        return codexAccount(result, fallbackPlan: nil, locations: [shortPath(home)], source: nil)
    }

    private static func codexAccount(_ result: Result<Data, FetchError>, fallbackPlan: String?,
                                     locations: [String], source: String?) -> UsageAccount {
        switch result.flatMap({ decode(CodexUsage.self, from: $0) }) {
        case .success(let usage):
            UsageAccount(provider: "codex", plan: (usage.planType ?? fallbackPlan).map(capitalized),
                         locations: locations, source: source, windows: codexWindows(usage))
        case .failure(let error):
            UsageAccount(provider: "codex", plan: fallbackPlan.map(capitalized), locations: locations,
                         source: source, windows: [],
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
            return UsageWindow(id: id, kind: kind, label: label, usedPercent: percent, resetsAt: resetsAt, duration: seconds)
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

    // MARK: - CLIProxyAPI hubs

    private struct HubAuthFile: Decodable {
        struct IdToken: Decodable {
            let chatgptAccountId: String?
            let chatgptPlanType: String?
        }

        let id: String?
        let authIndex: String
        let provider: String
        let email: String?
        let disabled: Bool?
        let idToken: IdToken?
    }

    private struct HubAuthFiles: Decodable { let files: [HubAuthFile] }
    private struct HubApiResponse: Decodable {
        let statusCode: Int
        let body: String
    }

    public struct HubError: Error, Sendable, Equatable {
        public let message: String
    }

    /// How many Claude or Codex accounts the hub pools, so Settings can confirm a key before saving it.
    @concurrent
    public static func hubAccountCount(url: String, managementKey: String) async -> Result<Int, HubError> {
        await hubAccounts(url: url, managementKey: managementKey).map(\.count)
    }

    private static func readHubs(_ hubs: [UsageHub]) async -> ([UsageAccount], [String]) {
        var accounts: [UsageAccount] = []
        var errors: [String] = []
        for hub in hubs {
            guard let key = hub.managementKey, !key.isEmpty else {
                errors.append("\(hub.label): no management key saved")
                continue
            }
            switch await hubAccounts(url: hub.url, managementKey: key) {
            case .failure(let error):
                errors.append("\(hub.label): \(error.message)")
            case .success(let files):
                accounts += await withTaskGroup(of: UsageAccount.self) { group in
                    for file in files {
                        group.addTask { await readHubAccount(file, hub: hub, managementKey: key) }
                    }
                    var read: [UsageAccount] = []
                    for await account in group { read.append(account) }
                    return read.sorted { $0.locations.first ?? "" < $1.locations.first ?? "" }
                }
            }
        }
        return (accounts, errors)
    }

    private static func hubAccounts(url: String, managementKey: String) async -> Result<[HubAuthFile], HubError> {
        guard let endpoint = hubURL(url, path: "auth-files") else {
            return .failure(HubError(message: "The hub URL isn't valid"))
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")
        switch await send(request).flatMap({ decode(HubAuthFiles.self, from: $0) }) {
        case .failure(.status(401)), .failure(.status(403)):
            return .failure(HubError(message: "The hub rejected the management key"))
        case .failure(let error):
            return .failure(HubError(message: error.message(signIn: "")))
        case .success(let list):
            return .success(list.files.filter { $0.disabled != true && ["claude", "codex"].contains($0.provider) })
        }
    }

    private static func readHubAccount(_ file: HubAuthFile, hub: UsageHub, managementKey: String) async -> UsageAccount {
        let locations = [file.email ?? file.id ?? file.authIndex]
        if file.provider == "codex" {
            let headers = codexHeaders(accountId: file.idToken?.chatgptAccountId)
            let result = await fetchViaHub(hub, managementKey: managementKey, authIndex: file.authIndex,
                                           url: codexUsageURL, headers: headers)
            return codexAccount(result, fallbackPlan: file.idToken?.chatgptPlanType, locations: locations,
                                source: hub.label)
        }
        let result = await fetchViaHub(hub, managementKey: managementKey, authIndex: file.authIndex,
                                       url: claudeUsageURL, headers: claudeHeaders)
        return claudeAccount(result, plan: nil, locations: locations, source: hub.label)
    }

    /// The hub makes the provider call with the account's own token in place of `$TOKEN$`.
    private static func fetchViaHub(_ hub: UsageHub, managementKey: String, authIndex: String, url: URL,
                                    headers: [String: String]) async -> Result<Data, FetchError> {
        guard let endpoint = hubURL(hub.url, path: "api-call") else {
            return .failure(.network("The hub URL isn't valid"))
        }
        var header = headers
        header["Authorization"] = "Bearer $TOKEN$"
        let body: [String: Any] = ["auth_index": authIndex, "method": "GET", "url": url.absoluteString,
                                   "header": header]
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await send(request).flatMap { decode(HubApiResponse.self, from: $0) }.flatMap { response in
            guard (200 ..< 300).contains(response.statusCode) else { return .failure(.status(response.statusCode)) }
            return .success(Data(response.body.utf8))
        }
    }

    private static func hubURL(_ base: String, path: String) -> URL? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), let scheme = components.scheme,
              ["http", "https"].contains(scheme), components.host != nil
        else { return nil }
        components.path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path += "/v0/management/\(path)"
        components.query = nil
        return components.url
    }

    // MARK: - Shared

    enum FetchError: Error {
        case network(String)
        case status(Int)
        case decoding

        func message(signIn: String) -> String {
            switch self {
            case .status(401), .status(403): signIn.isEmpty ? "The login was rejected" : signIn
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

    static let snakeCaseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func fetch(_ url: URL, token: String, headers: [String: String]) async -> Result<Data, FetchError> {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        return await send(request)
    }

    static func send(_ request: URLRequest) async -> Result<Data, FetchError> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { return .failure(.status(status)) }
        return .success(data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, FetchError> {
        (try? snakeCaseDecoder.decode(T.self, from: data)).map(Result.success) ?? .failure(.decoding)
    }

    /// Anthropic sends fractional seconds; a formatter parses either way but only one form at a time.
    static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    static func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Generic passwords through `/usr/bin/security`. Items it creates it may read back without a
/// permission prompt, which is also how Claude Code stores its own login.
public enum KeychainCLI {
    public static func read(service: String, account: String? = nil) -> Data? {
        var arguments = ["find-generic-password", "-s", service, "-w"]
        if let account { arguments += ["-a", account] }
        guard let result = run(arguments), result.0 == 0 else { return nil }
        return result.1
    }

    @discardableResult
    public static func write(service: String, account: String, value: String) -> Bool {
        run(["add-generic-password", "-U", "-s", service, "-a", account, "-w", value])?.0 == 0
    }

    public static func delete(service: String, account: String) {
        _ = run(["delete-generic-password", "-s", service, "-a", account])
    }

    private static func run(_ arguments: [String]) -> (Int32, Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
