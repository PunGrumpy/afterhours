import Foundation

/// Providers beyond Claude Code and Codex, each read from the login its own tool keeps on this Mac.
/// Every reader answers nil when the tool isn't signed in, so Macs without it never see a row.
extension UsageLimits {
    static func readOtherProviders() async -> [UsageAccount] {
        async let opencode = readOpenCode()
        async let copilot = readCopilot()
        async let cursor = readCursor()
        async let grok = readGrok()
        return await [opencode, copilot, cursor, grok].compactMap { $0 }
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

    /// The Cursor app keeps its login in a SQLite state store, which `sqlite3` reads without a prompt;
    /// the CLI's file login is the fallback. Its Keychain item would ask permission, so it isn't used.
    private static func cursorLogin() -> (token: String, plan: String?, location: String)? {
        let state = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        if FileManager.default.fileExists(atPath: state.path) {
            func value(_ key: String) -> String? {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
                process.arguments = ["-readonly", state.path, "SELECT value FROM ItemTable WHERE key = '\(key)'"]
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return nil }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return process.terminationStatus == 0 && !text.isEmpty ? text : nil
            }
            if let token = value("cursorAuth/accessToken") {
                return (token, value("cursorAuth/stripeMembershipType").map(capitalized), "Cursor app")
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
}
