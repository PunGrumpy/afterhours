import AfterhoursCore
import AppKit
import SwiftUI

/// Stronger with Increase Contrast; the background turns solid with Reduce Transparency.
private struct Palette {
    static let blue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let green = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)

    let contrast: ColorSchemeContrast
    private var increased: Bool { contrast == .increased }

    var secondaryText: Color { .white.opacity(increased ? 0.85 : 0.55) }
    var tertiaryText: Color { .white.opacity(increased ? 0.75 : 0.45) }
    var hairline: Color { .white.opacity(increased ? 0.35 : 0.1) }
    var fill: Color { .white.opacity(increased ? 0.22 : 0.1) }
    var hoverFill: Color { .white.opacity(increased ? 0.32 : 0.18) }
    var track: Color { .white.opacity(increased ? 0.3 : 0.15) }
    var idleRow: Double { increased ? 0.7 : 0.45 }

    static func background(reduceTransparency: Bool) -> Color {
        Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255).opacity(reduceTransparency ? 1 : 0.82)
    }
}

private protocol Themed: View {
    var contrast: ColorSchemeContrast { get }
}

private extension Themed {
    var palette: Palette { Palette(contrast: contrast) }
}

/// Every animation in the menu. Hover and hotkey changes stay instant on purpose.
private enum Motion {
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let fade = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    /// A spring, so a switch flipped again mid-flight reverses smoothly.
    static let knob = Animation.spring(duration: 0.25, bounce: 0)
}

struct MenuView: View, Themed {
    let model: AppModel
    @Bindable var prefs: Preferences
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            if prefs.lidClosedMode && !model.lidProof {
                HStack(spacing: 8) {
                    Text("On battery, closing the lid sleeps your Mac")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ChipButton(title: "Set up…") {
                        dismiss()
                        Task { model.installLidControl() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            divider
            BatterySection(battery: model.battery, prefs: prefs)
            divider
            agents
            divider
            limits
            pause
            divider
            VStack(spacing: 2) {
                MenuItem(title: "Settings…", shortcut: "⌘,") {
                    dismiss()
                    openSettings()
                    NSApp.activate()
                }
                .keyboardShortcut(",")
                MenuItem(title: "Quit Afterhours", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 300)
        .foregroundStyle(.white)
        .background(Palette.background(reduceTransparency: reduceTransparency))
        .background(MenuWindow {
            if prefs.usageLimits { model.usage.refresh(minimumAge: UsageMonitor.menuInterval) }
        })
        .animation(Motion.fade, value: model.lastError)
        .animation(Motion.fade, value: model.usage.accounts.isEmpty)
    }

    private var divider: some View {
        Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 16)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            MascotBadge(state: model.state)
            VStack(alignment: .leading, spacing: 2) {
                Text("Afterhours")
                    .font(.system(size: 15, weight: .bold))
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(statusLine(now: context.date))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(model.state.key)
                        .transition(.blurFade)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.fade, value: model.state.key)
            Toggle("Keep your Mac awake while agents work", isOn: $prefs.enabled)
                .toggleStyle(PillSwitch())
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func statusLine(now: Date) -> String {
        switch model.state {
        case .holding where model.holdReason != .working:
            if case .waitingForYou(let until?) = model.holdReason {
                return "Waiting for you until \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "Waiting for you while sessions are open"
        case .holding:
            let seconds = Int(now.timeIntervalSince(model.holdingSince ?? now))
            let elapsed = "\(seconds / 3600)h \(String(format: "%02d", seconds / 60 % 60))m"
            return model.lidProof ? "Awake for \(elapsed) · lid can close" : "Awake for \(elapsed) · keep lid open"
        case .idle: return "Idle. Your Mac can sleep"
        case .disabled: return "Off. Your Mac sleeps normally"
        case .paused(let until): return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        case .blocked(let reason): return "Released. \(reason)"
        }
    }

    // MARK: Agents

    private var agents: some View {
        let summaries = model.agentSummaries
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Agents")
                Spacer()
                Text(model.workingCount == 0 ? "None working" : "\(model.workingCount) working")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(palette.tertiaryText)
            }
            if summaries.isEmpty {
                Text("No coding agents found")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.tertiaryText)
            } else {
                VStack(spacing: 8) {
                    ForEach(summaries) { AgentRow(summary: $0) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Limits

    /// Hidden until a login is found, so Macs without Claude Code or Codex never see it.
    @ViewBuilder
    private var limits: some View {
        let accounts = model.usage.accounts
        if prefs.usageLimits, !accounts.isEmpty {
            let providers = Set(accounts.map(\.provider))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Limits")
                    Spacer()
                    if let checkedAt = model.usage.checkedAt {
                        Text(model.usage.refreshing ? "Checking…" : "As of \(checkedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
                ForEach(accounts) { account in
                    UsageAccountRow(account: account, showLocations: accounts.count > providers.count)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .transition(.opacity)
            divider
        }
    }

    // MARK: Pause

    private var pause: some View {
        HStack {
            SectionTitle("Pause")
            Spacer()
            if model.pausedUntil != nil {
                ChipButton(title: "Resume") { model.resume() }
            } else {
                HStack(spacing: 8) {
                    ChipButton(title: "30 min") { model.pause(minutes: 30) }
                    ChipButton(title: "1 hour") { model.pause(minutes: 60) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Pieces

private struct MascotBadge: View, Themed {
    let state: HoldState
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let mood = Mug.Mood(state)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(state.isHolding ? Palette.blue : palette.fill)
            Image(nsImage: Mug.image(mood, size: 26))
                .renderingMode(.template)
                .foregroundStyle(.white.opacity(state.isHolding ? 1 : 0.7))
                .id(mood)
                .transition(.blurFade)
        }
        .frame(width: 32, height: 32)
        .animation(Motion.fade, value: mood)
        .animation(Motion.fade, value: state.isHolding)
        .accessibilityHidden(true)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 15, weight: .bold))
    }
}

private struct BatterySection: View, Themed {
    let battery: BatteryStatus
    let prefs: Preferences
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Battery")
            if let percent = battery.percent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(color(percent)).frame(width: geo.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 7)
                .padding(.top, 10)
                HStack {
                    Text(battery.charging ? "\(percent)%, charging" : battery.onAC ? "\(percent)%, plugged in" : "\(percent)% left")
                        .fontWeight(.medium)
                    Spacer()
                    Text(cutoff).foregroundStyle(palette.tertiaryText)
                }
                .font(.system(size: 12).monospacedDigit())
                .padding(.top, 8)
            } else {
                Text("On AC power")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var cutoff: String {
        if prefs.onlyWhenPluggedIn { return "Plugged in only" }
        return prefs.batteryThreshold > 0 ? "Stops below \(prefs.batteryThreshold)%" : "No cutoff"
    }

    private func color(_ percent: Int) -> Color {
        if prefs.batteryThreshold > 0, percent < prefs.batteryThreshold { return Palette.red }
        if percent < max(prefs.batteryThreshold, 10) + 10 { return Palette.orange }
        return Palette.green
    }
}

private struct AgentRow: View, Themed {
    let summary: AgentSummary
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(id: summary.id)
            Text(summary.name)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.working > 0 {
                status(summary.sessions == 1 ? "1 session" : "\(summary.sessions) sessions", dot: Palette.green)
            } else if summary.waiting > 0 {
                status("Needs you", dot: Palette.orange)
            } else {
                Text("Idle").font(.system(size: 12)).foregroundStyle(palette.tertiaryText)
            }
        }
        .opacity(isActive ? 1 : palette.idleRow)
        .animation(Motion.fade, value: isActive)
        .accessibilityElement(children: .combine)
    }

    private var isActive: Bool { summary.working + summary.waiting > 0 }

    private func status(_ text: String, dot: Color) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12).monospacedDigit()).foregroundStyle(palette.secondaryText)
            Circle().fill(dot).frame(width: 7, height: 7)
        }
    }
}

private struct UsageAccountRow: View, Themed {
    let account: UsageAccount
    /// Two logins of one provider show where each lives.
    let showLocations: Bool
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                AgentIcon(id: account.provider)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showLocations {
                    Text(account.locations.joined(separator: " "))
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            if let error = account.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(account.windows) { UsageBar(window: $0) }
        }
    }

    private var title: String {
        let name = AgentKind.named(account.provider)?.displayName ?? account.provider
        return account.plan.map { "\(name) · \($0)" } ?? name
    }
}

private struct UsageBar: View, Themed {
    let window: UsageWindow
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(color).frame(width: geo.size.width * window.usedPercent / 100)
                    }
                }
                .frame(height: 5)
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
                Text(reset(now: context.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
                    .frame(width: 66, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.label), \(percent)% used, \(reset(now: context.date))")
        }
        .animation(Motion.fade, value: window.usedPercent)
    }

    private var percent: Int { Int(window.usedPercent.rounded()) }

    private var color: Color {
        if window.usedPercent >= 90 { return Palette.red }
        if window.usedPercent >= 75 { return Palette.orange }
        return Palette.green
    }

    /// Soon as a countdown, otherwise the day and time.
    private func reset(now: Date) -> String {
        guard let at = window.resetsAt else { return "" }
        let minutes = Int(at.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "resets now" }
        if minutes < 60 { return "in \(minutes)m" }
        if minutes < 24 * 60 { return "in \(minutes / 60)h \(String(format: "%02d", minutes % 60))m" }
        return at.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

private struct AgentIcon: View, Themed {
    let id: String
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(palette.fill)
            if let logo = Self.logo(for: id) {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 22, height: 22)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private static var cache: [String: NSImage?] = [:]

    private static func logo(for id: String) -> NSImage? {
        if let cached = cache[id] { return cached }
        let logo = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "agents")
            .flatMap(NSImage.init(contentsOf:))
        logo?.isTemplate = true
        cache[id] = logo
        return logo
    }
}

private struct ChipButton: View, Themed {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? palette.hoverFill : palette.fill))
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
    }
}

private struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

private struct MenuItem: View, Themed {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? .white.opacity(0.8) : palette.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Palette.blue : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PillSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillSwitchBody(isOn: configuration.$isOn)
    }
}

private struct PillSwitchBody: View, Themed {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? Palette.blue : palette.hoverFill)
                .frame(width: 40, height: 24)
                .overlay {
                    if reduceMotion {
                        // With Reduce Motion the knob cross-fades between ends instead of sliding.
                        ZStack {
                            knob.frame(maxWidth: .infinity, alignment: .leading).opacity(isOn ? 0 : 1)
                            knob.frame(maxWidth: .infinity, alignment: .trailing).opacity(isOn ? 1 : 0)
                        }
                    } else {
                        knob.frame(maxWidth: .infinity, alignment: isOn ? .trailing : .leading)
                    }
                }
                .animation(reduceMotion ? Motion.fade : Motion.knob, value: isOn)
        }
        .buttonStyle(PressScale())
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
            .frame(width: 20, height: 20)
            .padding(2)
    }
}

/// The menu is designed dark only, so force the popover window's appearance. Also reports each time
/// the window comes on screen, which SwiftUI's `onAppear` doesn't promise for a menu bar extra.
private struct MenuWindow: NSViewRepresentable {
    let onShow: () -> Void

    func makeNSView(context: Context) -> WatchingView {
        let view = WatchingView()
        view.onShow = onShow
        return view
    }

    func updateNSView(_ nsView: WatchingView, context: Context) {
        nsView.onShow = onShow
    }

    final class WatchingView: NSView {
        var onShow: () -> Void = {}
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.window?.occlusionState.contains(.visible) == true else { return }
                    self.onShow()
                }
            }
            if window.occlusionState.contains(.visible) { onShow() }
        }
    }
}

// MARK: - Transitions

private struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.opacity(active ? 0 : 1).blur(radius: active ? 2 : 0)
    }
}

private extension AnyTransition {
    /// The blur makes two states read as one changing element, not two overlapping ones.
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

private extension HoldState {
    /// Changes with the state, not with its payload, so ticking times don't restart transitions.
    var key: String {
        switch self {
        case .holding: "holding"
        case .idle: "idle"
        case .disabled: "disabled"
        case .paused: "paused"
        case .blocked: "blocked"
        }
    }
}
