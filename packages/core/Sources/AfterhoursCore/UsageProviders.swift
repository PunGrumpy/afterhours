import Foundation
import os

/// Providers beyond Claude Code and Codex, each read from the login its own tool keeps on this Mac.
/// Every reader answers nil when the tool isn't signed in, so Macs without it never see a row.
extension UsageLimits {
    static func readOtherProviders() async -> [UsageAccount] {
        async let opencode = readOpenCode()
        async let copilot = readCopilot()
        async let cursor = readCursor()
        async let grok = readGrok()
        async let antigravity = readAntigravity()
        return await [opencode, copilot, cursor, grok].compactMap { $0 } + antigravity
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func readJSON(at url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    // MARK: - OpenCode Go

    private struct OpenCodeUsage: Decodable {
        struct Window: Decodable {
            let percent: Double?
            let resetsAt: String?
        }

        struct Usage: Decodable {
            let rolling: Window?
            let weekly: Window?
            let monthly: Window?
        }

        let usage: Usage?
    }

    static let openCodeUsageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    /// `opencode-go` in OpenCode's auth file holds the Go subscription's API key.
    private static func readOpenCode() async -> UsageAccount? {
        let environment = ProcessInfo.processInfo.environment
        let dataDir = environment["OPENCODE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("opencode") }
            ?? home.appendingPathComponent(".local/share/opencode")
        guard let auth = readJSON(at: dataDir.appendingPathComponent("auth.json")),
              let go = auth["opencode-go"] as? [String: Any], go["type"] as? String == "api",
              let key = go["key"] as? String, !key.isEmpty
        else { return nil }
        let locations = [shortPath(dataDir)]
        switch await fetch(openCodeUsageURL, token: key, headers: [:]).flatMap({ decode(OpenCodeUsage.self, from: $0) }) {
        case .failure(.status(403)):
            return nil  // Signed in to Zen, not to Go.
        case .failure(let error):
            return UsageAccount(provider: "opencode", plan: "Go", locations: locations, windows: [],
                                error: error.message(signIn: "Run opencode once to refresh its login"))
        case .success(let usage):
            let windows = [("rolling", UsageWindow.Kind.session, "Session", usage.usage?.rolling),
                           ("weekly", .weekly, "Weekly", usage.usage?.weekly),
                           ("monthly", .monthly, "Monthly", usage.usage?.monthly)]
                .compactMap { id, kind, label, window in
                    window?.percent.map {
                        UsageWindow(id: id, kind: kind, label: label, usedPercent: $0,
                                    resetsAt: window?.resetsAt.flatMap(parseISO8601))
                    }
                }
            return UsageAccount(provider: "opencode", plan: "Go", locations: locations, windows: windows)
        }
    }

    // MARK: - Copilot

    static let copilotUsageURL = URL(string: "https://api.github.com/copilot_internal/user")!

    /// The OAuth token Copilot's editor plugins save, or the one `gh auth login` wrote to its config.
    private static func copilotToken() -> String? {
        let config = home.appendingPathComponent(".config")
        for name in ["apps.json", "hosts.json"] {
            guard let hosts = readJSON(at: config.appendingPathComponent("github-copilot/\(name)")) else { continue }
            for (host, value) in hosts where host.hasPrefix("github.com") {
                if let token = (value as? [String: Any])?["oauth_token"] as? String, !token.isEmpty { return token }
            }
        }
        guard let yaml = try? String(contentsOf: config.appendingPathComponent("gh/hosts.yml"), encoding: .utf8) else {
            return nil
        }
        var inGitHub = false
        for line in yaml.split(separator: "\n") {
            if !line.hasPrefix(" ") { inGitHub = line.hasPrefix("github.com:") }
            guard inGitHub else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("oauth_token:") {
                return trimmed.dropFirst("oauth_token:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func readCopilot() async -> UsageAccount? {
        guard let token = copilotToken() else { return nil }
        var request = URLRequest(url: copilotUsageURL, timeoutInterval: timeout)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode/1.100.0", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        let locations = ["github.com"]
        let body: [String: Any]
        switch await send(request) {
        case .failure(let error):
            return UsageAccount(provider: "copilot", plan: nil, locations: locations, windows: [],
                                error: error.message(signIn: "Sign in to Copilot again"))
        case .success(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return UsageAccount(provider: "copilot", plan: nil, locations: locations, windows: [],
                                    error: FetchError.decoding.message(signIn: ""))
            }
            body = json
        }
        let plan = (body["copilot_plan"] as? String).map { $0.replacingOccurrences(of: "_", with: " ") }.map(capitalized)
        let resetsAt = (body["quota_reset_date"] as? String).flatMap { text in
            parseISO8601(text) ?? parseISO8601(text + "T00:00:00Z")
        }
        let snapshots = body["quota_snapshots"] as? [String: Any] ?? [:]
        let windows = [("premium_interactions", "Credits"), ("chat", "Chat"), ("completions", "Completions")]
            .compactMap { key, label -> UsageWindow? in
                guard let bucket = snapshots[key] as? [String: Any] else { return nil }
                let entitlement = (bucket["entitlement"] as? NSNumber)?.doubleValue
                let remaining = (bucket["remaining"] as? NSNumber)?.doubleValue
                if bucket["unlimited"] as? Bool == true || entitlement == -1 || remaining == -1 || entitlement == 0 {
                    return nil
                }
                let used: Double
                if let percentRemaining = (bucket["percent_remaining"] as? NSNumber)?.doubleValue {
                    used = 100 - percentRemaining
                } else if let entitlement, entitlement > 0, let remaining {
                    used = (entitlement - remaining) / entitlement * 100
                } else {
                    return nil
                }
                return UsageWindow(id: key, kind: .monthly, label: label, usedPercent: used, resetsAt: resetsAt)
            }
        return UsageAccount(provider: "copilot", plan: plan, locations: locations, windows: windows)
    }

    // MARK: - Cursor

    private struct CursorUsage: Decodable {
        struct PlanUsage: Decodable {
            let totalPercentUsed: Double?
            let autoPercentUsed: Double?
            let apiPercentUsed: Double?
        }

        let billingCycleEnd: Double?
        let planUsage: PlanUsage?
    }

    static let cursorUsageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!

    /// Reads one value from a VS Code-style state store with `-init /dev/null`, so the user's sqliterc can't add headers.
    static func sqliteValue(database: URL, key: String, environment: [String: String]? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        let quoted = key.replacingOccurrences(of: "'", with: "''")
        process.arguments = ["-init", "/dev/null", "-readonly", database.path,
                             "SELECT value FROM ItemTable WHERE key = '\(quoted)'"]
        if let environment { process.environment = environment }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !text.isEmpty ? text : nil
    }

    /// The Cursor app keeps its login in a SQLite state store, which `sqlite3` reads without a prompt;
    /// the CLI's file login is the fallback. Its Keychain item would ask permission, so it isn't used.
    private static func cursorLogin() -> (token: String, plan: String?, location: String)? {
        let state = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        if FileManager.default.fileExists(atPath: state.path) {
            if let token = sqliteValue(database: state, key: "cursorAuth/accessToken") {
                return (token, sqliteValue(database: state, key: "cursorAuth/stripeMembershipType").map(capitalized),
                        "Cursor app")
            }
        }
        let file = home.appendingPathComponent(".cursor/auth.json")
        if let token = readJSON(at: file)?["accessToken"] as? String, !token.isEmpty {
            return (token, nil, shortPath(file))
        }
        return nil
    }

    private static func readCursor() async -> UsageAccount? {
        guard let login = cursorLogin() else { return nil }
        var request = URLRequest(url: cursorUsageURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("cli", forHTTPHeaderField: "x-cursor-client-type")
        request.httpBody = Data("{}".utf8)
        switch await send(request).flatMap({ decode(CursorUsage.self, from: $0) }) {
        case .failure(let error):
            return UsageAccount(provider: "cursor", plan: login.plan, locations: [login.location], windows: [],
                                error: error.message(signIn: "Sign in to Cursor again"))
        case .success(let usage):
            let resetsAt = usage.billingCycleEnd.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            let windows = [("total", "Plan", usage.planUsage?.totalPercentUsed),
                           ("auto", "Auto", usage.planUsage?.autoPercentUsed),
                           ("api", "API", usage.planUsage?.apiPercentUsed)]
                .compactMap { id, label, used in
                    used.map { UsageWindow(id: id, kind: .monthly, label: label, usedPercent: $0, resetsAt: resetsAt) }
                }
            return UsageAccount(provider: "cursor", plan: login.plan, locations: [login.location], windows: windows)
        }
    }

    // MARK: - Grok Build

    private struct GrokBilling: Decodable {
        struct Period: Decodable {
            let type: String?
            let end: String?
        }

        struct Config: Decodable {
            let creditUsagePercent: Double?
            let currentPeriod: Period?
        }

        let config: Config?
    }

    static let grokBillingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    private static func readGrok() async -> UsageAccount? {
        let file = home.appendingPathComponent(".grok/auth.json")
        guard let entries = readJSON(at: file) else { return nil }
        let entry = entries.values.compactMap { $0 as? [String: Any] }
            .first { ($0["auth_mode"] as? String) != "api_key" && ($0["key"] as? String)?.isEmpty == false }
        guard let key = entry?["key"] as? String else { return nil }
        let locations = [entry?["email"] as? String ?? shortPath(file)]
        switch await fetch(grokBillingURL, token: key, headers: [:]).flatMap({ decode(GrokBilling.self, from: $0) }) {
        case .failure(let error):
            return UsageAccount(provider: "grok", plan: nil, locations: locations, windows: [],
                                error: error.message(signIn: "Run grok login again"))
        case .success(let billing):
            guard let used = billing.config?.creditUsagePercent else {
                return UsageAccount(provider: "grok", plan: nil, locations: locations, windows: [])
            }
            let period = billing.config?.currentPeriod?.type?.replacingOccurrences(of: "USAGE_PERIOD_TYPE_", with: "")
            let kind: UsageWindow.Kind = period == "WEEKLY" ? .weekly : .monthly
            let window = UsageWindow(id: "credits", kind: kind, label: kind == .weekly ? "Weekly" : "Monthly",
                                     usedPercent: used, resetsAt: billing.config?.currentPeriod?.end.flatMap(parseISO8601))
            return UsageAccount(provider: "grok", plan: nil, locations: locations, windows: [window])
        }
    }

    // MARK: - Antigravity

    private struct AntigravityLogin: Decodable {
        let clientId: String
        let clientSecret: String
        let refreshToken: String
        let projectId: String?
    }

    private struct GoogleToken: Decodable {
        let accessToken: String
        let expiresIn: Double
        let idToken: String?
    }

    private struct AntigravityTiers: Decodable {
        struct Tier: Decodable { let name: String? }
        let paidTier: Tier?
    }

    private struct AntigravityQuota: Decodable {
        struct Bucket: Decodable {
            let bucketId: String
            let window: String?
            let remainingFraction: Double?
            let resetTime: String?
            let disabled: Bool?
        }

        struct Group: Decodable {
            let displayName: String?
            let buckets: [Bucket]?
        }

        let groups: [Group]?
        let buckets: [Bucket]?
    }

    private struct AntigravitySession {
        let accessToken: String
        let expiresAt: Date
        let email: String?
        let plan: String?
    }

    static let googleTokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    /// The stable endpoint, then the daily one Antigravity's own builds call.
    static let antigravityHosts = ["https://cloudcode-pa.googleapis.com", "https://daily-cloudcode-pa.googleapis.com"]

    private static let antigravityUserAgent: String = {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x64"
        #endif
        return "antigravity/hub/1.0.0 (aidev_client; os_type=darwin; arch=\(architecture); cl=963137146)"
    }()

    /// Access tokens by refresh token, so Google is asked for a new one once an hour instead of on every read.
    private static let antigravitySessions = OSAllocatedUnfairLock(initialState: [String: AntigravitySession]())

    /// The Google sign-in Antigravity's ACP agent saves under its Gemini home, which T3 Code points at a profile of its own.
    static func antigravityLogins(home: URL, geminiHome: URL? = nil) -> [(file: URL, location: String)] {
        let gemini = geminiHome ?? home.appendingPathComponent(".gemini")
        let profiles = home.appendingPathComponent(".t3/userdata/providers/antigravity")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: profiles.path)) ?? []
        var logins = [(file: gemini, location: shortPath(gemini))]
        logins += names.sorted().map { (file: profiles.appendingPathComponent($0), location: "T3 Code") }
        return logins.map { (file: $0.file.appendingPathComponent("antigravity-acp/acp_token.json"), location: $0.location) }
            .filter { FileManager.default.fileExists(atPath: $0.file.path) }
    }

    private static func readAntigravity() async -> [UsageAccount] {
        let geminiHome = ProcessInfo.processInfo.environment["GEMINI_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        }
        var accounts: [UsageAccount] = []
        var seen: Set<String> = []
        for (file, fallback) in antigravityLogins(home: home, geminiHome: geminiHome) {
            guard let data = try? Data(contentsOf: file),
                  let login = try? snakeCaseDecoder.decode(AntigravityLogin.self, from: data)
            else { continue }
            let session = await antigravitySession(login)
            // One Google account signed in twice is one row.
            let location = (try? session.get())?.email ?? fallback
            guard seen.insert(location).inserted else { continue }
            switch session {
            case .failure(let error):
                accounts.append(UsageAccount(provider: "antigravity", plan: nil, locations: [location], windows: [],
                                             error: error.message(signIn: antigravitySignIn)))
            case .success(let session):
                let result = await antigravityCall("retrieveUserQuotaSummary", token: session.accessToken,
                                                   body: login.projectId.map { ["project": $0] } ?? [:])
                if case .failure(.status(401)) = result {
                    antigravitySessions.withLock { $0[login.refreshToken] = nil }
                }
                if let account = antigravityAccount(result, plan: session.plan, locations: [location]) {
                    accounts.append(account)
                }
            }
        }
        return accounts
    }

    private static let antigravitySignIn = "Sign in to Antigravity again"

    /// Antigravity saves only a long-lived Google login, so each hour it's exchanged for an access token
    /// that stays in memory. Google keeps the saved login valid, and nothing is written back.
    private static func antigravitySession(_ login: AntigravityLogin) async -> Result<AntigravitySession, FetchError> {
        let cached = antigravitySessions.withLock { $0[login.refreshToken] }
        if let cached, cached.expiresAt.timeIntervalSinceNow > 60 { return .success(cached) }
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "client_id", value: login.clientId),
                           URLQueryItem(name: "client_secret", value: login.clientSecret),
                           URLQueryItem(name: "refresh_token", value: login.refreshToken),
                           URLQueryItem(name: "grant_type", value: "refresh_token")]
        var request = URLRequest(url: googleTokenURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // URLComponents leaves "+" alone, which a form reads as a space.
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        switch await send(request).flatMap({ decode(GoogleToken.self, from: $0) }) {
        case .failure(.status(400)):
            return .failure(.status(401))  // Google answers 400 for a login it revoked.
        case .failure(let error):
            return .failure(error)
        case .success(let token):
            let tiers = await antigravityCall("loadCodeAssist", token: token.accessToken, body: [:])
                .flatMap { decode(AntigravityTiers.self, from: $0) }
            let session = AntigravitySession(
                accessToken: token.accessToken, expiresAt: Date().addingTimeInterval(token.expiresIn),
                email: token.idToken.flatMap(jwtPayload)?["email"] as? String,
                plan: (try? tiers.get())?.paidTier?.name)
            antigravitySessions.withLock { $0[login.refreshToken] = session }
            return .success(session)
        }
    }

    /// A rejected token is rejected on every host, so only other failures move on to the next one.
    static func antigravityTriesNextHost(after result: Result<Data, FetchError>) -> Bool {
        switch result {
        case .success, .failure(.status(401)): false
        case .failure: true
        }
    }

    /// Answers with the first host that succeeds or rejects the token, or the last one's failure.
    private static func antigravityCall(_ operation: String, token: String,
                                        body: [String: String]) async -> Result<Data, FetchError> {
        var result: Result<Data, FetchError> = .failure(.network("Antigravity has no usage endpoint"))
        for host in antigravityHosts {
            guard let url = URL(string: "\(host)/v1internal:\(operation)") else { continue }
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(antigravityUserAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            result = await send(request)
            if !antigravityTriesNextHost(after: result) { break }
        }
        return result
    }

    /// Nil when the account reports no five-hour or weekly allowance, as with an API key or a Cloud project.
    static func antigravityAccount(_ result: Result<Data, FetchError>, plan: String?,
                                   locations: [String]) -> UsageAccount? {
        let quota: AntigravityQuota
        switch result.flatMap({ decode(AntigravityQuota.self, from: $0) }) {
        case .failure(let error):
            return UsageAccount(provider: "antigravity", plan: plan, locations: locations, windows: [],
                                error: error.message(signIn: antigravitySignIn))
        case .success(let decoded):
            quota = decoded
        }
        var groups = (quota.groups ?? []).filter { $0.buckets?.isEmpty == false }
        if groups.isEmpty { groups = [AntigravityQuota.Group(displayName: nil, buckets: quota.buckets)] }
        var windows: [UsageWindow] = []
        for group in groups {
            for bucket in group.buckets ?? [] where bucket.disabled != true {
                let (kind, span): (UsageWindow.Kind, String)
                switch bucket.window {
                case "5h": (kind, span) = (.session, "Session")
                case "weekly": (kind, span) = (.weekly, "Weekly")
                default: continue
                }
                guard let left = bucket.remainingFraction, !windows.contains(where: { $0.id == bucket.bucketId })
                else { continue }
                let family: String
                if bucket.bucketId.hasPrefix("gemini-") {
                    family = "Gemini"
                } else if bucket.bucketId.hasPrefix("3p-") {
                    family = "Claude & GPT"  // Both draw on one allowance.
                } else {
                    family = group.displayName?.trimmingCharacters(in: .whitespaces) ?? bucket.bucketId
                }
                windows.append(UsageWindow(id: bucket.bucketId, kind: kind, label: "\(span) · \(family)",
                                           usedPercent: (1 - left) * 100,
                                           resetsAt: bucket.resetTime.flatMap(parseISO8601)))
            }
        }
        return windows.isEmpty ? nil
            : UsageAccount(provider: "antigravity", plan: plan, locations: locations, windows: windows)
    }
}
