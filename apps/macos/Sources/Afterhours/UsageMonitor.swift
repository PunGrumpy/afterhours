import AfterhoursCore
import Foundation
import Observation

/// Reads subscription quotas at most every few minutes and keeps the last good reading.
@Observable
final class UsageMonitor {
    private(set) var snapshot = UsageSnapshot()
    private(set) var checkedAt: Date?
    private(set) var refreshing = false

    var accounts: [UsageAccount] { snapshot.accounts }

    /// Between background checks while agents work.
    static let interval: TimeInterval = 5 * 60
    /// Between checks triggered by opening the menu.
    static let menuInterval: TimeInterval = 60

    /// Skips when a reading younger than `minimumAge` exists or one is in flight.
    func refresh(hubs: [UsageHub], minimumAge: TimeInterval = interval) {
        guard !refreshing else { return }
        if let checkedAt, Date().timeIntervalSince(checkedAt) < minimumAge { return }
        refreshing = true
        Task { [weak self] in
            let fresh = await UsageLimits.read(claudeConfigDirectories: ClaudeHooks.configDirectories(), hubs: hubs)
            guard let self else { return }
            // A failed read keeps the last bars beside its message, so a flaky network doesn't blank them.
            let previousAccounts = accounts
            let merged = fresh.accounts.map { account in
                guard account.error != nil, account.windows.isEmpty,
                      let previous = previousAccounts.first(where: { $0.id == account.id }), !previous.windows.isEmpty
                else { return account }
                return UsageAccount(provider: account.provider, plan: previous.plan, locations: account.locations,
                                    source: account.source, windows: previous.windows, error: account.error)
            }
            snapshot = UsageSnapshot(accounts: merged, hubErrors: fresh.hubErrors)
            checkedAt = Date()
            refreshing = false
        }
    }

    /// Sample data for previews and snapshots.
    func seed(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        checkedAt = Date()
    }

    func clear() {
        snapshot = UsageSnapshot()
        checkedAt = nil
    }
}
