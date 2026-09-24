import AppKit
import AfterhoursCore
import Observation
import UserNotifications

struct AgentSummary: Identifiable {
    let id: String
    let name: String
    let sessions: Int
    let working: Int
    let waiting: Int
}

struct AgentSession {
    let agentId: String
    let agentName: String
    let state: AgentState
}

enum HoldReason: Equatable {
    case working
    /// A nil `until` waits until every session closes.
    case waitingForYou(until: Date?)
}

enum HoldState: Equatable {
    case disabled
    case paused(until: Date)
    case holding
    case blocked(String)  // agents are working, but a safety rule says no
    case idle

    var isHolding: Bool { self == .holding }
}

@Observable
final class AppModel {
    let prefs = Preferences()

    private(set) var sessions: [AgentSession] = []
    private(set) var state: HoldState = .idle
    private(set) var battery = Power.battery()
    private(set) var lidControlInstalled = LidControl.isInstalled
    private(set) var holdingSince: Date?
    private(set) var holdReason: HoldReason = .working
    /// Agents whose CLI is installed, so the menu can list them even when not running.
    private(set) var installedAgents: Set<String> = []
    private(set) var pausedUntil: Date?
    private(set) var lastError: String?

    /// Interrupting Claude Code with Esc fires no Stop hook, so a silent "working" session is stuck.
    @ObservationIgnored private let stuckAfter: TimeInterval = 15 * 60
    /// Agents without hooks count as working for this long after their last CPU activity.
    @ObservationIgnored private let activeWindow: TimeInterval = 45

    @ObservationIgnored private let assertion = SleepAssertion()
    @ObservationIgnored private var tracker = ActivityTracker()
    @ObservationIgnored private var lastWorkingAt: Date?
    @ObservationIgnored private var sleepDisabledByUs = false
    @ObservationIgnored private var warnedLowBattery = false
    @ObservationIgnored private var hotKey: HotKey?

    init() {
        // Recover from a previous crash that left lid sleep disabled.
        if Power.sleepDisabled, LidControl.isInstalled { LidControl.setSleepDisabled(false) }
        try? ClaudeHooks.installHookBinary()

        prefs.onChange = { [weak self] in self?.tick() }
        hotKey = HotKey.toggle { [weak self] in self?.toggleEnabled() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        }
        if prefs.notifications, Self.canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        tick()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                self?.tick()
            }
        }
        Task { [weak self] in
            let installed = await AgentKind.findInstalled()
            self?.installedAgents = installed
        }
    }

    // MARK: - Actions

    func toggleEnabled() { prefs.enabled.toggle() }

    func pause(minutes: Int) {
        pausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        tick()
    }

    func resume() {
        pausedUntil = nil
        tick()
    }

    func installLidControl() { changeLidControl(LidControl.install) }

    func uninstallLidControl() { changeLidControl(LidControl.uninstall) }

    private func changeLidControl(_ change: () throws -> Void) {
        do {
            try change()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        lidControlInstalled = LidControl.isInstalled
        sleepDisabledByUs = false
        tick()
    }

    // MARK: - Loop

    func tick() {
        let now = Date()
        if let until = pausedUntil, until <= now { pausedUntil = nil }
        battery = Power.battery()
        sessions = collectSessions(now: now)

        let working = sessions.contains { $0.state == .working }
        if working { lastWorkingAt = now }
        if sessions.isEmpty { lastWorkingAt = nil }
        let reason: HoldReason? = working ? .working : waitForYou(now: now)
        if let reason { holdReason = reason }

        let next: HoldState
        if !prefs.enabled {
            next = .disabled
        } else if let until = pausedUntil {
            next = .paused(until: until)
        } else if reason == nil {
            next = .idle
        } else if let reason = blocker() {
            next = .blocked(reason)
        } else {
            next = .holding
        }
        apply(next)
        warnIfBatteryLow(next)
    }

    /// Warns once per hold, 5 points before the battery cutoff.
    private func warnIfBatteryLow(_ state: HoldState) {
        guard state.isHolding, !battery.onAC, prefs.batteryThreshold > 0, let percent = battery.percent else {
            warnedLowBattery = false
            return
        }
        guard percent <= prefs.batteryThreshold + 5, !warnedLowBattery else { return }
        warnedLowBattery = true
        announce("Battery is getting low",
                 body: "Afterhours lets your Mac sleep at \(prefs.batteryThreshold)%. It's at \(percent)% now.")
    }

    /// The wait limit counts from when an agent last worked.
    private func waitForYou(now: Date) -> HoldReason? {
        guard let last = lastWorkingAt, !sessions.isEmpty else { return nil }
        let minutes = battery.onAC ? prefs.pluggedInWaitMinutes : prefs.batteryWaitMinutes
        if minutes == Preferences.untilSessionsClose { return .waitingForYou(until: nil) }
        let until = last.addingTimeInterval(TimeInterval(minutes * 60))
        return until > now ? .waitingForYou(until: until) : nil
    }

    private func blocker() -> String? {
        if ProcessInfo.processInfo.thermalState == .critical { return "Your Mac is too hot" }
        if prefs.respectLowPowerMode, Power.lowPowerMode { return "Low Power Mode is on" }
        guard !battery.onAC else { return nil }
        if prefs.onlyWhenPluggedIn { return "Your Mac isn't plugged in" }
        if let percent = battery.percent, prefs.batteryThreshold > 0, percent < prefs.batteryThreshold {
            return "Battery is below \(prefs.batteryThreshold)%"
        }
        return nil
    }

    private func apply(_ next: HoldState) {
        let wasHolding = state.isHolding
        state = next

        if next.isHolding {
            assertion.hold(reason: "Afterhours: coding agents are working", lidClosed: prefs.lidClosedMode)
        } else {
            assertion.release()
        }

        let wantLid = next.isHolding && prefs.lidClosedMode && lidControlInstalled
        if wantLid != sleepDisabledByUs {
            if LidControl.setSleepDisabled(wantLid) {
                sleepDisabledByUs = wantLid
                lastError = nil
            } else {
                lastError = "Couldn't run pmset. Reinstall lid-closed mode in Settings."
                lidControlInstalled = LidControl.isInstalled
            }
        }

        guard wasHolding != next.isHolding else { return }
        holdingSince = next.isHolding ? Date() : nil
        if next.isHolding {
            announce("Keeping your Mac awake", body: summary)
            if prefs.turnDisplayOff { Power.displaySleepNow() }
        } else {
            announce("Your Mac can sleep again", body: releaseReason(next))
            // Disabling `disablesleep` doesn't put a closed Mac to sleep on its own.
            if Power.lidClosed { Power.sleepNow() }
        }
    }

    private func releaseAll() {
        assertion.release()
        if sleepDisabledByUs { LidControl.setSleepDisabled(false) }
    }

    // MARK: - Sessions

    private func collectSessions(now: Date) -> [AgentSession] {
        let records = loadHookRecords()
        let hookedAgents = Set(records.map(\.agent))
        let detected = tracker.scan(enabled: prefs.detectedAgents.union(hookedAgents))
        let activity = Dictionary(detected.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let hookedPids = Set(records.compactMap(\.pid))

        var result: [AgentSession] = records.map { record in
            var state = record.state
            if state == .working, let pid = record.pid, let info = activity[pid],
               now.timeIntervalSince(max(info.lastActive ?? .distantPast, record.updatedAt)) > stuckAfter {
                state = .idle
            }
            return AgentSession(
                agentId: record.agent,
                agentName: AgentKind.named(record.agent)?.displayName ?? record.agent,
                state: state
            )
        }

        for info in detected where !hookedPids.contains(info.pid) && prefs.detectedAgents.contains(info.kind.id) {
            let active = info.lastActive.map { now.timeIntervalSince($0) < activeWindow } ?? false
            result.append(AgentSession(agentId: info.kind.id, agentName: info.kind.displayName,
                                       state: active ? .working : .idle))
        }

        return result.sorted { ($0.state.sortKey, $0.agentName) < ($1.state.sortKey, $1.agentName) }
    }

    /// Reads hook session files, deleting ones whose agent process has exited.
    private func loadHookRecords() -> [SessionRecord] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: AfterhoursPaths.sessions, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder.afterhours.decode(SessionRecord.self, from: data)
            else { return nil }
            let orphaned = record.pid.map { !Proc.isAlive($0) }
                ?? (Date().timeIntervalSince(record.updatedAt) > 6 * 3600)
            if orphaned {
                try? fm.removeItem(at: url)
                return nil
            }
            return record
        }
    }

    // MARK: - Presentation

    var workingCount: Int { sessions.filter { $0.state == .working }.count }

    var agentSummaries: [AgentSummary] {
        let byAgent = Dictionary(grouping: sessions, by: \.agentId)
        let known = AgentKind.all.map(\.id)
        let ids = known.filter { installedAgents.contains($0) || byAgent[$0] != nil }
            + byAgent.keys.filter { !known.contains($0) }.sorted()
        return ids.map { id in
            let group = byAgent[id] ?? []
            return AgentSummary(
                id: id,
                name: AgentKind.named(id)?.displayName ?? group.first?.agentName ?? id,
                sessions: group.count,
                working: group.filter { $0.state == .working }.count,
                waiting: group.filter { $0.state == .waiting }.count
            )
        }
    }

    /// Whether holding survives closing the lid.
    var lidProof: Bool { prefs.lidClosedMode && (lidControlInstalled || battery.onAC) }

    var summary: String {
        switch (workingCount, holdReason) {
        case (0, .waitingForYou(until: nil)): "Waiting for you while agent sessions are open."
        case (0, .waitingForYou(let until?)):
            "Waiting for you until \(until.formatted(date: .omitted, time: .shortened))."
        case (1, _): "1 agent working"
        default: "\(workingCount) agents working"
        }
    }

    /// UNUserNotificationCenter throws when the binary isn't running from an app bundle.
    private static let canNotify = Bundle.main.bundleIdentifier != nil

    private func releaseReason(_ state: HoldState) -> String {
        switch state {
        case .blocked(let reason): reason
        case .disabled: "You turned Afterhours off."
        case .paused: "You paused Afterhours."
        default: "All agents finished."
        }
    }

    private func announce(_ title: String, body: String) {
        if !prefs.sound.isEmpty { NSSound(named: NSSound.Name(prefs.sound))?.play() }
        guard prefs.notifications, Self.canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

private extension AgentState {
    var sortKey: Int {
        switch self {
        case .working: 0
        case .waiting: 1
        case .idle: 2
        }
    }
}
