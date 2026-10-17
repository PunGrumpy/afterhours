import AfterhoursCore
import Foundation
import Observation

/// Reads subscription quotas at most every few minutes and keeps the last good reading.
@Observable
final class UsageMonitor {
    private(set) var snapshot = UsageSnapshot()
    private(set) var checkedAt: Date?
    private(set) var refreshing = false
    private var reading: Task<Void, Never>?
    /// Hubs to read again once the current read ends, because Settings changed them mid-read.
    private var pendingHubs: [UsageHub]?

    var accounts: [UsageAccount] { snapshot.accounts }

    /// Between background checks while agents work.
    static let interval: TimeInterval = 5 * 60
    /// Between checks triggered by opening the menu.
    static let menuInterval: TimeInterval = 60

    /// Skips when a reading younger than `minimumAge` exists, and runs a forced one again after the read in flight.
    func refresh(hubs: [UsageHub], minimumAge: TimeInterval = interval) {
        if refreshing {
            // A forced refresh comes from a Settings change, which the read in flight doesn't include.
            if minimumAge == 0 { pendingHubs = hubs }
            return
        }
        if let checkedAt, Date().timeIntervalSince(checkedAt) < minimumAge { return }
        refreshing = true
        reading = Task { [weak self] in
            let fresh = await UsageLimits.read(claudeConfigDirectories: ClaudeHooks.configDirectories(), hubs: hubs)
            guard let self else { return }
            // Limits was turned off mid-read, and `clear()` already reset the state.
            guard !Task.isCancelled else { return }
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
            if let hubs = pendingHubs {
                pendingHubs = nil
                refresh(hubs: hubs, minimumAge: 0)
            }
        }
    }

    /// Sample data for previews and snapshots.
    func seed(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        checkedAt = Date()
    }

    func clear() {
        reading?.cancel()
        reading = nil
        pendingHubs = nil
        refreshing = false
        snapshot = UsageSnapshot()
        checkedAt = nil
    }
}
