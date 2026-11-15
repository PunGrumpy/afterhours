import Foundation

/// A usage snapshot with the time each account last read successfully, and the one decoder for its saved form.
public struct UsageReading: Sendable, Equatable {
    public var snapshot: UsageSnapshot
    /// When each account last read successfully, keyed by `UsageAccount.id`.
    public var readAt: [String: Date]

    public init(snapshot: UsageSnapshot = UsageSnapshot(), readAt: [String: Date] = [:]) {
        self.snapshot = snapshot
        self.readAt = readAt
    }

    /// The oldest read among the accounts that show bars, so the time on screen is the age of the oldest bar.
    public var asOf: Date? {
        snapshot.accounts.compactMap { $0.windows.isEmpty ? nil : readAt[$0.id] }.min()
    }

    /// Drops windows whose reset has passed, because their share used belongs to a period that ended.
    public func current(at now: Date) -> UsageReading {
        var accounts: [UsageAccount] = []
        for account in snapshot.accounts {
            let windows = account.windows.filter { $0.resetsAt.map { $0 > now } ?? true }
            // An error still has something to say once its bars are gone.
            guard !windows.isEmpty || account.error != nil else { continue }
            accounts.append(windows.count == account.windows.count ? account : UsageAccount(
                provider: account.provider, plan: account.plan, locations: account.locations, source: account.source,
                windows: windows, error: account.error))
        }
        let shown = Set(accounts.map(\.id))
        return UsageReading(snapshot: UsageSnapshot(accounts: accounts, hubErrors: snapshot.hubErrors),
                            readAt: readAt.filter { shown.contains($0.key) })
    }

    /// What to do with the saved file once a read has finished.
    public enum FileAction: Sendable, Equatable {
        case write, delete, keep
    }

    /// Writes only on a success and deletes only when nothing is signed in, so a failed read can't wipe the bars it failed to refresh.
    public static func fileAction(after fresh: UsageSnapshot) -> FileAction {
        if fresh.hasSuccess { return .write }
        return fresh.accounts.isEmpty && fresh.hubErrors.isEmpty ? .delete : .keep
    }

    /// Nil for anything but a version 1 file, so a damaged or newer file reads as no saved reading.
    public init?(saved data: Data, now: Date) {
        guard let file = try? JSONDecoder.afterhours.decode(SavedFile.self, from: data), file.version == SavedFile.current
        else { return nil }
        var accounts: [UsageAccount] = []
        var readAt: [String: Date] = [:]
        for saved in file.accounts {
            // Built through the validating initializers, so a hand-edited share or reset can't pass as read.
            let windows = saved.windows.compactMap { window -> UsageWindow? in
                guard let kind = UsageWindow.Kind(rawValue: window.kind) else { return nil }
                return UsageWindow(id: window.id, kind: kind, label: window.label, usedPercent: window.usedPercent,
                                   resetsAt: window.resetsAt, duration: window.duration)
            }
            // The menu reads the first location of a single account, so a hand-edited file without one can't stand.
            guard !saved.locations.isEmpty else { continue }
            let account = UsageAccount(provider: saved.provider, plan: saved.plan, locations: saved.locations,
                                       source: saved.source, windows: windows)
            accounts.append(account)
            readAt[account.id] = saved.readAt
        }
        self = UsageReading(snapshot: UsageSnapshot(accounts: accounts), readAt: readAt).current(at: now)
    }

    /// Only bars and where they came from. An error, a hub error or a login is never written.
    public func saved() -> Data? {
        let accounts = snapshot.accounts.compactMap { account -> SavedFile.Account? in
            guard !account.windows.isEmpty, let readAt = readAt[account.id] else { return nil }
            let windows = account.windows.map {
                SavedFile.Window(id: $0.id, kind: $0.kind.rawValue, label: $0.label, usedPercent: $0.usedPercent,
                                 resetsAt: $0.resetsAt, duration: $0.duration)
            }
            return SavedFile.Account(provider: account.provider, plan: account.plan, locations: account.locations,
                                     source: account.source, readAt: readAt, windows: windows)
        }
        return try? JSONEncoder.afterhours.encode(SavedFile(version: SavedFile.current, accounts: accounts))
    }
}

extension UsageSnapshot {
    /// Whether at least one account read without an error.
    public var hasSuccess: Bool {
        accounts.contains { $0.error == nil }
    }
}

/// The file's shape. A change in what a field means needs a new version number.
private struct SavedFile: Codable {
    static let current = 1

    struct Window: Codable {
        let id: String
        let kind: Int
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        let duration: TimeInterval
    }

    struct Account: Codable {
        let provider: String
        let plan: String?
        let locations: [String]
        let source: String?
        let readAt: Date
        let windows: [Window]
    }

    let version: Int
    let accounts: [Account]
}
