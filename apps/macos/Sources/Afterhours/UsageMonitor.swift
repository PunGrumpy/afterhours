import AfterhoursCore
import Foundation
import Observation

/// Reads subscription quotas at most every few minutes and keeps the last good reading.
@Observable
final class UsageMonitor {
    private(set) var accounts: [UsageAccount] = []
    private(set) var checkedAt: Date?
    private(set) var refreshing = false

    /// Between background checks while agents work.
    static let interval: TimeInterval = 5 * 60
    /// Between checks triggered by opening the menu.
    static let menuInterval: TimeInterval = 60

    /// Skips when a reading younger than `minimumAge` exists or one is in flight.
    func refresh(minimumAge: TimeInterval = interval) {
        guard !refreshing else { return }
        if let checkedAt, Date().timeIntervalSince(checkedAt) < minimumAge { return }
        refreshing = true
        Task { [weak self] in
            let fresh = await UsageLimits.read(claudeConfigDirectories: ClaudeHooks.configDirectories())
            guard let self else { return }
            // A failed read keeps the last bars beside its message, so a flaky network doesn't blank them.
            accounts = fresh.map { account in
                guard account.error != nil, account.windows.isEmpty,
                      let previous = accounts.first(where: { $0.id == account.id }), !previous.windows.isEmpty
                else { return account }
                return UsageAccount(provider: account.provider, plan: previous.plan, locations: account.locations,
                                    windows: previous.windows, error: account.error)
            }
            checkedAt = Date()
            refreshing = false
        }
    }

    func clear() {
        accounts = []
        checkedAt = nil
    }
}
