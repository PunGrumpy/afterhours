import AfterhoursCore
import Foundation

/// Every account of one provider read together, the way T3 Code's Limits page pools them.
struct ProviderPool: Identifiable {
    /// One window across the pool: the mean share used, the soonest reset, and each account's own window.
    struct Window: Identifiable {
        let id: String
        let kind: UsageWindow.Kind
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        /// In account order; nil where an account doesn't report this window.
        let segments: [UsageWindow?]

        var leftPercent: Int { Int((100 - usedPercent).rounded()) }

        /// The pool's outlook: mean projected share left and the earliest run-out, over accounts with a pace.
        func pace(now: Date) -> UsageWindow.Pace? {
            let paces = segments.compactMap { $0?.pace(now: now) }
            guard !paces.isEmpty else { return nil }
            return UsageWindow.Pace(
                elapsed: paces.map(\.elapsed).reduce(0, +) / Double(paces.count),
                projectedLeft: paces.map(\.projectedLeft).reduce(0, +) / Double(paces.count),
                runsOutAt: paces.compactMap(\.runsOutAt).min()
            )
        }
    }

    let provider: String
    /// Soonest session reset first, so segments keep their column across windows.
    let accounts: [UsageAccount]
    let windows: [Window]
    /// "location: reason" for accounts that reported nothing.
    let errors: [String]

    var id: String { provider }
    var name: String { AgentKind.named(provider)?.displayName ?? provider }

    /// The plan when every account shares one.
    var plan: String? {
        let plans = Set(accounts.compactMap(\.plan))
        return plans.count == 1 ? plans.first : nil
    }

    var fullest: Window? { windows.max { $0.usedPercent < $1.usedPercent } }

    static func build(_ accounts: [UsageAccount]) -> [ProviderPool] {
        let byProvider = Dictionary(grouping: accounts, by: \.provider)
        let known = AgentKind.all.map(\.id)
        let order = known.filter { byProvider[$0] != nil } + byProvider.keys.filter { !known.contains($0) }.sorted()
        return order.map { provider in
            let sorted = byProvider[provider]!.sorted { sessionReset($0) < sessionReset($1) }
            return ProviderPool(provider: provider, accounts: sorted, windows: pooledWindows(sorted),
                                errors: sorted.compactMap { account in
                                    account.error.map { "\(account.locations.joined(separator: " ")): \($0)" }
                                })
        }
    }

    private static func sessionReset(_ account: UsageAccount) -> Date {
        account.windows.first { $0.kind == .session }?.resetsAt ?? account.windows.first?.resetsAt ?? .distantFuture
    }

    private static func pooledWindows(_ accounts: [UsageAccount]) -> [Window] {
        var order: [String] = []
        var first: [String: UsageWindow] = [:]
        for window in accounts.flatMap(\.windows) where first[window.id] == nil {
            order.append(window.id)
            first[window.id] = window
        }
        return order.map { id in
            let template = first[id]!
            let segments = accounts.map { $0.windows.first { $0.id == id } }
            let present = segments.compactMap { $0?.usedPercent }
            return Window(id: id, kind: template.kind, label: template.label,
                          usedPercent: present.reduce(0, +) / Double(max(present.count, 1)),
                          resetsAt: segments.compactMap { $0?.resetsAt }.min(), segments: segments)
        }
        .sorted { ($0.kind, order.firstIndex(of: $0.id)!) < ($1.kind, order.firstIndex(of: $1.id)!) }
    }
}
