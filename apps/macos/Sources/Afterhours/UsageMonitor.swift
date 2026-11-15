import AfterhoursCore
import Foundation
import Observation

/// Reads subscription quotas at most every few minutes and keeps the last good reading, in memory and in one small file.
@Observable
final class UsageMonitor {
    private(set) var reading = UsageReading()
    private(set) var refreshing = false
    /// Throttles reads and is never shown, because a failed attempt says nothing about the age of the bars.
    private var attemptedAt: Date?
    /// A first failed read doesn't throttle the next one, because the network may be back by then.
    private var lastReadFailed = false
    /// False once the file is known to be gone, so `clear()` on every tick doesn't hit the disk.
    private var fileMayExist = true
    private var task: Task<Void, Never>?
    /// Hubs to read again once the current read ends, because Settings changed them mid-read.
    private var pendingHubs: [UsageHub]?
    /// Nil for previews, so a render never reads or writes the saved file.
    @ObservationIgnored private let file: URL?

    init(file: URL?) {
        self.file = file
    }

    var snapshot: UsageSnapshot { reading.snapshot }
    var accounts: [UsageAccount] { reading.snapshot.accounts }
    /// When the oldest bars on screen were read.
    var asOf: Date? { reading.asOf }

    /// Between background checks while agents work.
    static let interval: TimeInterval = 5 * 60
    /// Between checks triggered by opening the menu.
    static let menuInterval: TimeInterval = 60

    /// Shows the last saved reading until the first read of this launch ends.
    func restore(now: Date = Date()) {
        guard let file, let data = try? Data(contentsOf: file), let saved = UsageReading(saved: data, now: now) else { return }
        reading = saved
    }

    /// Drops the windows whose reset has passed since the reading was made.
    func expire(now: Date = Date()) {
        let current = reading.current(at: now)
        if current != reading { reading = current }
    }

    /// Skips when an attempt younger than `minimumAge` exists, and runs a forced one again after the read in flight.
    func refresh(hubs: [UsageHub], minimumAge: TimeInterval = interval) {
        if refreshing {
            // A forced refresh comes from a Settings change, which the read in flight doesn't include.
            if minimumAge == 0 { pendingHubs = hubs }
            return
        }
        if let attemptedAt, Date().timeIntervalSince(attemptedAt) < minimumAge { return }
        refreshing = true
        task = Task { [weak self] in
            let fresh = await UsageLimits.read(claudeConfigDirectories: ClaudeHooks.configDirectories(), hubs: hubs)
            guard let self else { return }
            // Limits was turned off mid-read, and `clear()` already reset the state.
            guard !Task.isCancelled else { return }
            let now = Date()
            reading = merge(fresh, into: reading.current(at: now), now: now)
            let action = UsageReading.fileAction(after: fresh)
            let failed = action == .keep
            if !failed || lastReadFailed { attemptedAt = now }
            lastReadFailed = failed
            refreshing = false
            switch action {
            case .write: save()
            case .delete: removeFile()
            case .keep: break
            }
            if let hubs = pendingHubs {
                pendingHubs = nil
                refresh(hubs: hubs, minimumAge: 0)
            }
        }
    }

    /// A failed read keeps the last bars beside its message, so a flaky network doesn't blank them, and their old time with them.
    private func merge(_ fresh: UsageSnapshot, into previous: UsageReading, now: Date) -> UsageReading {
        var readAt: [String: Date] = [:]
        let accounts = fresh.accounts.map { account -> UsageAccount in
            guard account.error != nil, account.windows.isEmpty,
                  let old = previous.snapshot.accounts.first(where: { $0.id == account.id }), !old.windows.isEmpty
            else {
                if account.error == nil { readAt[account.id] = now }
                return account
            }
            readAt[account.id] = previous.readAt[account.id]
            return UsageAccount(provider: account.provider, plan: old.plan, locations: account.locations,
                                source: account.source, windows: old.windows, error: account.error)
        }
        return UsageReading(snapshot: UsageSnapshot(accounts: accounts, hubErrors: fresh.hubErrors), readAt: readAt)
    }

    private func save() {
        guard let file, let data = reading.saved() else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileMayExist = true
        try? data.write(to: file, options: .atomic)
    }

    private func removeFile() {
        guard fileMayExist, let file else { return }
        fileMayExist = false
        try? FileManager.default.removeItem(at: file)
    }

    /// Sample data for previews and snapshots.
    func seed(_ reading: UsageReading) {
        self.reading = reading
    }

    func clear() {
        task?.cancel()
        task = nil
        pendingHubs = nil
        refreshing = false
        reading = UsageReading()
        attemptedAt = nil
        lastReadFailed = false
        removeFile()
    }
}
