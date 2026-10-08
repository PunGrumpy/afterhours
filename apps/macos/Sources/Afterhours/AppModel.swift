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

struct AgentSession: Equatable {
    let agentId: String
    let agentName: String
    let state: AgentState
}

@Observable
final class AppModel {
    let prefs: Preferences
    let usage = UsageMonitor()

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
    /// True when the shortcut is on in Settings but couldn't be registered.
    private(set) var hotKeyTaken = false

    /// Interrupting Claude Code with Esc fires no Stop hook, so a silent "working" session is stuck.
    @ObservationIgnored private let stuckAfter: TimeInterval = 15 * 60
    /// Agents without hooks count as working for this long after their last CPU activity.
    @ObservationIgnored private let activeWindow: TimeInterval = 45
    /// Between ticks while sessions are open or a hold is on, because CPU samples and wait deadlines need it.
    @ObservationIgnored private let busyInterval: TimeInterval = 4
    /// Between ticks with nothing to watch; a hook still wakes the loop at once through the sessions folder.
    @ObservationIgnored private let quietInterval: TimeInterval = 15
    /// Kept as one value, so a later pmset success clears this message and no other.
    private static let pmsetFailure = "Couldn't run pmset. Reinstall lid-closed mode in Settings."

    @ObservationIgnored private let assertion = SleepAssertion()
    @ObservationIgnored private var tracker = ActivityTracker()
    @ObservationIgnored private var lastWorkingAt: Date?
    @ObservationIgnored private var sleepDisabledByUs = false
    @ObservationIgnored private var warnedLowBattery = false
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var terminationSignals: [DispatchSourceSignal] = []
    @ObservationIgnored private var sleepGuard: Process?
    @ObservationIgnored private var sessionWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var hookTickPending = false
    /// Decoded session files by path, so an unchanged file isn't read and decoded again every tick.
    @ObservationIgnored private var recordCache: [URL: (modified: Date, record: SessionRecord)] = [:]

    init() {
        prefs = Preferences()
        // Recover from a previous crash that left lid sleep disabled.
        if Power.sleepDisabled, LidControl.isInstalled { LidControl.setSleepDisabled(false) }
        do { try ClaudeHooks.installHookBinary() } catch {
            lastError = "Couldn't install afterhours-hook: \(error.localizedDescription)"
        }

        prefs.onChange = { [weak self] in
            self?.syncHotKey()
            self?.tick()
        }
        syncHotKey()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        }
        // `kill`, `pkill`, a closed terminal, and updaters skip willTerminate; without this, `disablesleep 1`
        // outlives the app.
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.releaseAll() }
                exit(0)
            }
            source.resume()
            terminationSignals.append(source)
        }
        if prefs.notifications, Self.canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        tick()
        watchSessions()
        // The tolerance lets macOS coalesce this wakeup with others instead of waking the CPU just for it.
        Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.nextTickDelay ?? 4
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay / 4))
                self?.tick()
            }
        }
        Task { [weak self] in
            let installed = await AgentKind.findInstalled()
            if self?.installedAgents != installed { self?.installedAgents = installed }
        }
    }

    /// A model with sample state and no side effects, for rendering the menu outside the app.
    init(preview: Preferences) {
        prefs = preview
        state = .holding
        holdingSince = Date().addingTimeInterval(-83 * 60)
        installedAgents = ["claude", "codex", "opencode"]
        sessions = [
            AgentSession(agentId: "claude", agentName: "Claude Code", state: .working),
            AgentSession(agentId: "claude", agentName: "Claude Code", state: .working),
            AgentSession(agentId: "codex", agentName: "Codex", state: .idle),
        ]
        usage.seed(Self.sampleUsage)
    }

    private static var sampleUsage: UsageSnapshot {
        let now = Date()
        func window(_ id: String, _ kind: UsageWindow.Kind, _ label: String, _ used: Double, hours: Double) -> UsageWindow {
            UsageWindow(id: id, kind: kind, label: label, usedPercent: used, resetsAt: now.addingTimeInterval(hours * 3600))
        }
        func claude(_ locations: [String], source: String? = nil, _ session: Double, _ weekly: Double, _ fable: Double,
                    hours: Double) -> UsageAccount {
            UsageAccount(provider: "claude", plan: "Max", locations: locations, source: source, windows: [
                window("five_hour", .session, "Session", session, hours: hours),
                window("seven_day", .weekly, "Weekly", weekly, hours: 20 + hours),
                window("seven_day_fable", .weekly, "Weekly · Fable", fable, hours: 20 + hours),
            ])
        }
        return UsageSnapshot(accounts: [
            claude(["~/.claude", "~/.claude-nipa"], 2, 70, 100, hours: 1.3),
            claude(["~/.claude-pun"], 8, 50, 58, hours: 2.1),
            claude(["team@example.com"], source: "Thaipass", 60, 91, 72, hours: 4.0),
            UsageAccount(provider: "codex", plan: "Pro", locations: ["~/.codex"], windows: [
                window("primary", .session, "Session", 12, hours: 3.7),
                window("secondary", .weekly, "Weekly", 34, hours: 88),
            ]),
        ], hubErrors: ["Spare hub: The hub rejected the management key"])
    }

    // MARK: - Actions

    /// The mug looks the same off and idle, so a press that doesn't start or end a hold says what it did.
    func toggleEnabled() {
        let wasHolding = state.isHolding
        prefs.enabled.toggle()
        guard state.isHolding == wasHolding else { return }
        announce(prefs.enabled ? "Afterhours is on" : "Afterhours is off",
                 body: "You pressed ⌥⌘L. If another app needs that shortcut, turn it off in Settings > General.")
    }

    /// Registers ⌥⌘L only while the setting is on, so turning it off frees the keys at once.
    private func syncHotKey() {
        guard prefs.hotKeyEnabled != (hotKey != nil) else { return }
        hotKey?.unregister()
        hotKey = nil
        hotKeyTaken = false
        guard prefs.hotKeyEnabled else { return }
        hotKey = HotKey.toggle { [weak self] in self?.toggleEnabled() }
        hotKeyTaken = hotKey == nil
    }

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
        // An observed property notifies SwiftUI on every set, even an equal one, so unchanged values aren't written.
        let freshBattery = Power.battery()
        if freshBattery != battery { battery = freshBattery }
        let freshSessions = collectSessions(now: now)
        if freshSessions != sessions { sessions = freshSessions }

        let working = sessions.contains { $0.state == .working }
        lastWorkingAt = HoldPolicy.lastWorkingAt(previous: lastWorkingAt, working: working,
                                                 hasSessions: !sessions.isEmpty, now: now)
        let reason = HoldPolicy.reason(working: working, hasSessions: !sessions.isEmpty, lastWorkingAt: lastWorkingAt,
                                       onAC: battery.onAC, pluggedInWaitMinutes: prefs.pluggedInWaitMinutes,
                                       batteryWaitMinutes: prefs.batteryWaitMinutes, now: now)
        if let reason, reason != holdReason { holdReason = reason }

        let next = HoldPolicy.state(enabled: prefs.enabled, pausedUntil: pausedUntil, reason: reason, blocker: blocker())
        apply(next)
        warnIfBatteryLow(next)
        // The quota matters while agents burn it; otherwise opening the menu refreshes on demand.
        if (next.isHolding && working) || !prefs.usageLimits { refreshUsage() }
    }

    /// Opening the menu shows fresh sessions at once, even between quiet ticks.
    func menuOpened() {
        tick()
        if prefs.usageLimits { refreshUsage(minimumAge: UsageMonitor.menuInterval) }
    }

    private var nextTickDelay: TimeInterval {
        var delay = sessions.isEmpty && !state.isHolding ? quietInterval : busyInterval
        if let pausedUntil { delay = min(delay, max(pausedUntil.timeIntervalSinceNow, 1)) }
        return delay
    }

    /// Hooks write session files, so a change in that folder ticks right away instead of on the next timer.
    private func watchSessions() {
        try? FileManager.default.createDirectory(at: AfterhoursPaths.sessions, withIntermediateDirectories: true)
        let fd = open(AfterhoursPaths.sessions.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleHookTick() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        sessionWatcher = source
    }

    /// A burst of tool calls rewrites the files many times a second, so they share one tick.
    private func scheduleHookTick() {
        guard !hookTickPending else { return }
        hookTickPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.hookTickPending = false
            self?.tick()
        }
    }

    func refreshUsage(minimumAge: TimeInterval = UsageMonitor.interval) {
        guard prefs.usageLimits else { return usage.clear() }
        usage.refresh(hubs: prefs.hubs, minimumAge: minimumAge)
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

    private func blocker() -> String? {
        HoldPolicy.blocker(thermalCritical: ProcessInfo.processInfo.thermalState == .critical,
                           lowPowerMode: Power.lowPowerMode, respectLowPowerMode: prefs.respectLowPowerMode,
                           onAC: battery.onAC, onlyWhenPluggedIn: prefs.onlyWhenPluggedIn,
                           batteryPercent: battery.percent, batteryThreshold: prefs.batteryThreshold)
    }

    private func apply(_ next: HoldState) {
        let wasHolding = state.isHolding
        if next != state { state = next }

        if next.isHolding {
            assertion.hold(reason: "Afterhours: coding agents are working", lidClosed: prefs.lidClosedMode)
        } else {
            assertion.release()
        }

        let wantLid = next.isHolding && prefs.lidClosedMode && lidControlInstalled
        // Something else can turn it off under a hold, such as the guard of an Afterhours that quit a moment ago.
        if wantLid != sleepDisabledByUs || (wantLid && !Power.sleepDisabled) {
            if LidControl.setSleepDisabled(wantLid) {
                sleepDisabledByUs = wantLid
                if lastError == Self.pmsetFailure { lastError = nil }
                if wantLid { startSleepGuard() }
            } else {
                lastError = Self.pmsetFailure
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
            // A docked Mac with its lid shut is in use, so only force sleep when the lid would sleep it anyway.
            if Power.lidClosed, Power.lidClosedWouldSleep { Power.sleepNow() }
        }
    }

    private func releaseAll() {
        assertion.release()
        if sleepDisabledByUs { LidControl.setSleepDisabled(false) }
    }

    /// A crash or Force Quit skips `releaseAll()`, so a helper outside this process turns `disablesleep` off after it.
    private func startSleepGuard() {
        guard sleepGuard?.isRunning != true,
              let hook = Bundle.main.url(forAuxiliaryExecutable: "afterhours-hook") else { return }
        let process = Process()
        process.executableURL = hook
        process.arguments = ["--guard", String(getpid())]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil { sleepGuard = process }
    }

    // MARK: - Sessions

    private func collectSessions(now: Date) -> [AgentSession] {
        let records = loadHookRecords()
        let hookedAgents = Set(records.map(\.agent))
        let detected = tracker.scan(enabled: prefs.detectedAgents.union(hookedAgents))
        let activity = Dictionary(detected.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let hookedRoots = Set(records.compactMap { record in
            record.pid.flatMap { trackedRoot(of: $0, agent: record.agent, in: activity) }
        })

        var result: [AgentSession] = records.map { record in
            var state = record.state
            if state == .working {
                // Without a tracker entry, the hook's timestamps are all there is; every tool call refreshes them.
                let lastActive = record.pid.flatMap { trackedRoot(of: $0, agent: record.agent, in: activity) }
                    .flatMap { activity[$0]?.lastActive } ?? .distantPast
                if now.timeIntervalSince(max(lastActive, record.updatedAt)) > stuckAfter { state = .idle }
            }
            return AgentSession(
                agentId: record.agent,
                agentName: AgentKind.named(record.agent)?.displayName ?? record.agent,
                state: state
            )
        }

        for info in detected where !hookedRoots.contains(info.pid) && prefs.detectedAgents.contains(info.kind.id) {
            let active = info.lastActive.map { now.timeIntervalSince($0) < activeWindow } ?? false
            result.append(AgentSession(agentId: info.kind.id, agentName: info.kind.displayName,
                                       state: active ? .working : .idle))
        }

        return result.sorted { ($0.state.sortKey, $0.agentName) < ($1.state.sortKey, $1.agentName) }
    }

    /// The hook reports its own parent, which can sit below the pid the tracker chose as the agent's root.
    private func trackedRoot(of pid: Int32, agent: String, in activity: [Int32: ActivityTracker.Detected]) -> Int32? {
        var current = pid
        for _ in 0..<8 {
            if activity[current]?.kind.id == agent { return current }
            guard let parent = Proc.parent(current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    /// Reads hook session files, deleting ones whose agent process has exited.
    private func loadHookRecords() -> [SessionRecord] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: AfterhoursPaths.sessions,
                                                 includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let now = Date()
        var cache: [URL: (modified: Date, record: SessionRecord)] = [:]
        let records = files.filter { $0.pathExtension == "json" }.compactMap { url -> SessionRecord? in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            let record: SessionRecord
            if let cached = recordCache[url], cached.modified == modified {
                record = cached.record
            } else {
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder.afterhours.decode(SessionRecord.self, from: data)
                else { return nil }
                record = decoded
            }
            let orphaned = record.pid.map { !Proc.isAlive($0) }
                ?? (now.timeIntervalSince(record.updatedAt) > 6 * 3600)
            if orphaned {
                try? fm.removeItem(at: url)
                return nil
            }
            cache[url] = (modified, record)
            return record
        }
        recordCache = cache
        return records
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
