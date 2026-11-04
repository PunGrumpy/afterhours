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
    var card: Color { .white.opacity(increased ? 0.14 : 0.06) }
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
    /// Critically damped: nothing here carries momentum, so nothing overshoots. Reversible mid-flight.
    /// Under 300 ms because Limits opens and closes many times a day.
    static let settle = Animation.spring(duration: 0.25, bounce: 0)
    /// Changes this soon after the menu opens are the refresh that opening triggers, not something you watched happen.
    static let openGrace: TimeInterval = 0.15
}

private struct ShownAtKey: EnvironmentKey {
    static let defaultValue: Date? = .distantPast
}

private extension EnvironmentValues {
    /// When the menu last came on screen; nil while it is hidden.
    var menuShownAt: Date? {
        get { self[ShownAtKey.self] }
        set { self[ShownAtKey.self] = newValue }
    }
}

/// Animates a change to `value` only if you watch it happen: never on first render, when the menu
/// opens, or when a section expands, because `animation(_:value:)` fires only on the change itself.
private struct Settling<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.menuShownAt) private var shownAt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let watching = shownAt.map { Date().timeIntervalSince($0) > Motion.openGrace } ?? false
        content.animation(watching ? (reduceMotion ? Motion.fade : Motion.settle) : nil, value: value)
    }
}

private extension View {
    func settling(_ value: some Equatable) -> some View { modifier(Settling(value: value)) }

    /// A figure that rolls to its new digits; under Reduce Motion it cross-fades instead.
    func ticking(_ value: some Equatable) -> some View { modifier(TickingFigure()).settling(value) }
}

private struct TickingFigure: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText())
    }
}

/// The header's result and what it means, one entry per state.
private struct MenuHeadline: Equatable {
    let title: String
    let detail: String

    init(state: HoldState, reason: HoldReason, since: Date?, lidProof: Bool, now: Date) {
        switch (state, reason) {
        case (.holding, .working):
            let seconds = Int(now.timeIntervalSince(since ?? now))
            title = "Awake for \(seconds / 3600)h \(String(format: "%02d", seconds / 60 % 60))m"
            detail = lidProof ? "Lid can close" : "Keep the lid open"
        case (.holding, .waitingForYou(let until?)):
            title = "Waiting for you"
            detail = "Until \(until.formatted(date: .omitted, time: .shortened))"
        case (.holding, .waitingForYou(nil)):
            title = "Waiting for you"
            detail = "While sessions are open"
        case (.idle, _):
            title = "Idle"
            detail = "Your Mac can sleep"
        case (.disabled, _):
            title = "Off"
            detail = "Your Mac sleeps normally"
        case (.paused(let until), _):
            title = "Paused"
            detail = "Until \(until.formatted(date: .omitted, time: .shortened))"
        case (.blocked(let why), _):
            title = "Released"
            detail = why
        }
    }
}

struct MenuView: View, Themed {
    let model: AppModel
    @Bindable var prefs: Preferences
    /// Rendering to an image: no window to watch, and the window's own chrome is drawn here instead.
    var snapshot = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Providers the user opened or closed by hand; the rest open only when they need attention.
    @State private var openPools: [String: Bool] = [:]
    @State private var shownAt: Date?
    /// The last error text, kept while the error row folds away so its words don't vanish first.
    @State private var shownError = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Collapsible(expanded: model.lastError != nil, reduceMotion: reduceMotion) {
                Text(model.lastError ?? shownError)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Collapsible(expanded: showsLidWarning, reduceMotion: reduceMotion) {
                HStack(spacing: 8) {
                    Text("On battery, closing the lid sleeps your Mac")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ChipButton(title: "Install…") {
                        dismiss()
                        Task { model.installLidControl() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            divider
            BatterySection(battery: model.battery, prefs: prefs, timeLeft: model.holdTimeLeft)
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
        .background(Palette.background(reduceTransparency: reduceTransparency || snapshot))
        .background {
            if !snapshot {
                MenuWindow { visible in
                    shownAt = visible ? Date() : nil
                    if visible { model.menuOpened() }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: snapshot ? 10 : 0, style: .continuous))
        .overlay {
            if snapshot {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1)
            }
        }
        .padding(snapshot ? 24 : 0)
        .background(snapshot ? Color(red: 0.16, green: 0.18, blue: 0.24) : .clear)
        .environment(\.menuShownAt, snapshot ? .distantPast : shownAt)
        .onChange(of: model.lastError, initial: true) { _, error in
            if let error { shownError = error }
        }
        .animation(reduceMotion ? nil : Motion.settle, value: model.lastError != nil)
        .animation(reduceMotion ? nil : Motion.settle, value: showsLidWarning)
        .animation(Motion.fade, value: model.usage.accounts.isEmpty)
        .animation(reduceMotion ? nil : Motion.settle, value: prefs.limitsExpanded)
        .animation(reduceMotion ? nil : Motion.settle, value: openPools)
    }

    private var isPaused: Bool {
        if case .paused = model.state { return true }
        return false
    }

    private var showsLidWarning: Bool { prefs.lidClosedMode && !model.lidProof }

    private var divider: some View {
        Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 16)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            MascotBadge(state: model.state)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let headline = MenuHeadline(
                    state: model.state, reason: model.holdReason, since: model.holdingSince,
                    lidProof: model.lidProof, now: context.date
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline.title)
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .ticking(headline.title)
                    Text(headline.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(model.state.key)
                .transition(.blurFade)
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

    /// Hidden until a login is found, so Macs without Claude Code or Codex never see it. Accounts
    /// pool per provider like T3 Code: collapsed, one badge per provider shows its fullest window;
    /// expanded, each provider is one row that opens to a bar per window with a segment per account.
    @ViewBuilder
    private var limits: some View {
        let pools = ProviderPool.build(model.usage.accounts)
        if prefs.usageLimits, !pools.isEmpty || !model.usage.snapshot.hubErrors.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DisclosureRow(expanded: $prefs.limitsExpanded, title: "Limits") {
                    if prefs.limitsExpanded {
                        if let checkedAt = model.usage.checkedAt {
                            Text(model.usage.refreshing ? "Checking…" : "As of \(checkedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(palette.tertiaryText)
                        }
                    } else {
                        LimitsSummary(pools: pools, hubErrors: model.usage.snapshot.hubErrors)
                    }
                }
                Collapsible(expanded: prefs.limitsExpanded, reduceMotion: reduceMotion) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pools) { pool in
                            let expanded = openPools[pool.id] ?? PoolRows.needsAttention(pool)
                            PoolRows(pool: pool, expanded: expanded, reduceMotion: reduceMotion) {
                                openPools[pool.id] = !expanded
                            }
                        }
                        ForEach(model.usage.snapshot.hubErrors, id: \.self) { error in
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 10)
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
            ZStack(alignment: .trailing) {
                switch model.state {
                case .paused:
                    ChipButton(title: "Resume") { model.resume() }
                        .transition(.blurFade)
                default:
                    HStack(spacing: 8) {
                        ChipButton(title: "30 min") { model.pause(minutes: 30) }
                            .accessibilityLabel("Pause for 30 minutes")
                        ChipButton(title: "1 hour") { model.pause(minutes: 60) }
                            .accessibilityLabel("Pause for 1 hour")
                    }
                    .disabled(model.state == .disabled)
                    .transition(.blurFade)
                }
            }
            .animation(Motion.fade, value: isPaused)
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
            // Every mood stays in the tree so the swap only cross-fades and the tile is never empty.
            ForEach(Mug.Mood.allCases, id: \.self) { candidate in
                Image(nsImage: Mug.image(candidate, size: 26))
                    .renderingMode(.template)
                    .foregroundStyle(.white.opacity(state.isHolding ? 1 : 0.7))
                    .opacity(candidate == mood ? 1 : 0)
            }
        }
        .frame(width: 32, height: 32)
        .animation(Motion.fade, value: mood)
        .animation(Motion.fade, value: state.isHolding)
        .accessibilityHidden(true)
    }
}

private struct SectionTitle: View, Themed {
    /// The chevrons beside a title use the same font, so they sit on its baseline.
    static let font = Font.system(size: 12, weight: .semibold)

    let text: String
    @Environment(\.colorSchemeContrast) var contrast

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Self.font).foregroundStyle(palette.secondaryText)
    }
}

private struct BatterySection: View, Themed {
    let battery: BatteryStatus
    let prefs: Preferences
    let timeLeft: (minutes: Int, atCutoff: Bool)?
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Battery")
                Spacer()
                if let percent = battery.percent {
                    Text("\(percent)%")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .ticking(percent)
                }
            }
            if let percent = battery.percent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(color(percent)).frame(width: geo.size.width * CGFloat(percent) / 100)
                    }
                    .settling(percent)
                }
                .frame(height: 7)
                .padding(.top, 8)
                Text(caption)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// The time left already names the cutoff when one applies, so only the state needs it added.
    private var caption: String {
        if let timeLeft { return timeLeftText(timeLeft) }
        let state = battery.charging ? "Charging" : battery.onAC ? "Plugged in" : "On battery"
        return "\(state) · \(cutoff)"
    }

    private var spokenLabel: String {
        guard let percent = battery.percent else { return "Battery, on AC power" }
        return "Battery, \(percent)%\(battery.charging || battery.onAC ? "" : " left"), \(caption)"
    }

    /// Says when the hold ends, so you can tell before closing the lid whether tonight's work fits.
    private func timeLeftText(_ timeLeft: (minutes: Int, atCutoff: Bool)) -> String {
        guard timeLeft.minutes > 0 else { return "Releasing at the cutoff" }
        let hours = timeLeft.minutes / 60
        let minutes = timeLeft.minutes % 60
        let duration = hours > 0 ? "\(hours)h \(String(format: "%02d", minutes))m" : "\(minutes)m"
        return timeLeft.atCutoff
            ? "About \(duration) until it sleeps at \(prefs.batteryThreshold)%"
            : "About \(duration) of battery left"
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
            HStack(spacing: 12) {
                AgentIcon(id: summary.id)
                Text(summary.name)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(isActive ? 1 : palette.idleRow)
            Group {
                if summary.working > 0 {
                    status(summary.sessions == 1 ? "1 session" : "\(summary.sessions) sessions", dot: Palette.green)
                } else if summary.waiting > 0 {
                    status("Needs you", dot: Palette.orange)
                } else {
                    Text("Idle").font(.system(size: 12)).foregroundStyle(palette.tertiaryText)
                }
            }
            .id(statusKey)
            .transition(.blurFade)
        }
        .animation(Motion.fade, value: statusKey)
        .accessibilityElement(children: .combine)
    }

    private var isActive: Bool { summary.working + summary.waiting > 0 }

    /// Changes with the kind of status, not its count, so "1 session" becoming "2 sessions" stays in place.
    private var statusKey: String { summary.working > 0 ? "working" : summary.waiting > 0 ? "waiting" : "idle" }

    private func status(_ text: String, dot: Color) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12).monospacedDigit()).foregroundStyle(palette.secondaryText)
            Circle().fill(dot).frame(width: 7, height: 7)
        }
    }
}

/// Grows from nothing to its content's height and back. The content hangs from the bottom edge, so
/// it slides out from under the row above and returns the same way. With Reduce Motion the height
/// snaps and the content fades in place, because sliding what sits below is the motion it asks to avoid.
private struct Collapsible<Content: View>: View {
    let expanded: Bool
    let reduceMotion: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            } body: { view in
                Reveal(progress: expanded ? 1 : 0, hangsFromBottom: !reduceMotion) { view }
            }
            .clipped()
            .opacity(expanded ? 1 : 0)
            .animation(reduceMotion ? Motion.fade : Motion.settle, value: expanded)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
    }
}

/// Lays its content out at full height and reports only `progress` of it. The height is interpolated by the
/// layout itself, not copied from a measurement, so a section that grows inside another one moves it in step.
private struct Reveal: Layout {
    var progress: CGFloat
    let hangsFromBottom: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let top = hangsFromBottom ? bounds.maxY - size.height : bounds.minY
        content.place(at: CGPoint(x: bounds.minX, y: top), anchor: .topLeading,
                      proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

/// Dims on press-down at once and recovers on release, without moving the text it holds.
private struct PressDim: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(configuration.isPressed ? nil : Motion.press, value: configuration.isPressed)
    }
}

/// A section title that toggles its section, with a chevron that turns and a trailing summary.
private struct DisclosureRow<Trailing: View>: View, Themed {
    @Binding var expanded: Bool
    let title: String
    @ViewBuilder let trailing: Trailing
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        Button { expanded.toggle() } label: {
            // Symbols at the title's font size sit on its baseline by design; the scale only shrinks the glyph.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SectionTitle(title).fixedSize()
                Image(systemName: "chevron.right")
                    .font(SectionTitle.font)
                    .imageScale(.small)
                    .foregroundStyle(hovering ? palette.secondaryText : palette.tertiaryText)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                trailing.layoutPriority(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDim())
        .onHover { hovering = $0 }
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

/// One provider's emptiest pooled window, for the collapsed Limits row.
private struct PoolBadge: View, Themed {
    let pool: ProviderPool
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        HStack(spacing: 5) {
            AgentIcon(id: pool.provider, size: 18)
            if let worst = pool.fullest {
                Text("\(worst.leftPercent)%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(UsageColor.verdict(worst, now: Date()).color)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pool.spokenSummary)
    }
}

/// Every badge when they fit, else the troubled providers first and a count for the rest, so the row never wraps.
private struct LimitsSummary: View, Themed {
    let pools: [ProviderPool]
    let hubErrors: [String]
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let troubled = pools.filter(PoolRows.needsAttention)
        let reasons = hubErrors + troubled.map { "\($0.name) needs attention" }
        let now = Date()
        let severities = troubled.map { severity(of: $0, now: now) }
        let worstFirst = troubled.indices.sorted { lhs, rhs in
            severities[lhs] == severities[rhs] ? lhs < rhs : severities[lhs] > severities[rhs]
        }.map { troubled[$0] }
        let byUrgency = worstFirst + pools.filter { !PoolRows.needsAttention($0) }
        ViewThatFits(in: .horizontal) {
            candidate(pools, hiding: [], reasons: reasons)
            ForEach(Array((1..<max(pools.count, 1)).reversed()), id: \.self) { shown in
                candidate(Array(byUrgency.prefix(shown)), hiding: Array(byUrgency.dropFirst(shown)), reasons: reasons)
            }
        }
    }

    private func severity(of pool: ProviderPool, now: Date) -> UsageColor.Verdict {
        pool.windows.map { UsageColor.verdict($0, now: now) }.max() ?? .fine
    }

    private func candidate(_ shown: [ProviderPool], hiding hidden: [ProviderPool], reasons: [String]) -> some View {
        HStack(spacing: 8) {
            if !reasons.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.orange)
                    .help(reasons.joined(separator: "\n"))
                    .accessibilityLabel("Needs attention")
            }
            ForEach(shown) { PoolBadge(pool: $0) }
            if !hidden.isEmpty {
                Text("+\(hidden.count)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.tertiaryText)
                    .help(hidden.map(\.name).joined(separator: "\n"))
                    .accessibilityLabel("and \(hidden.count) more providers")
            }
        }
        .fixedSize()
    }
}

/// Bars show what's left, like the battery above them. Their color is a verdict on the whole window:
/// green while the burn rate lands with room to spare, orange when it lands inside the last tenth,
/// red when it runs out before the reset. Windows too young to project color by level instead.
private enum UsageColor {
    enum Verdict: Int, Comparable {
        case fine, tight, out

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Blue like the system's own usage meters, so quota never reads as battery.
        var color: Color {
            switch self {
            case .fine: Palette.blue
            case .tight: Palette.orange
            case .out: Palette.red
            }
        }
    }

    static func verdict(_ window: UsageWindow, now: Date) -> Verdict {
        if window.leftPercent.rounded() <= 0 { return .out }
        if let pace = window.pace(now: now) {
            return pace.projectedLeft <= 0 ? .out : pace.projectedLeft < 10 ? .tight : .fine
        }
        return window.leftPercent < 10 ? .out : window.leftPercent < 25 ? .tight : .fine
    }

    /// The worst account decides the pool's color.
    static func verdict(_ window: ProviderPool.Window, now: Date) -> Verdict {
        window.segments.compactMap { $0.map { verdict($0, now: now) } }.max() ?? .fine
    }
}

private extension ProviderPool {
    /// What VoiceOver reads for the provider, with the same verdict the colors show.
    var spokenSummary: String {
        guard let worst = fullest else { return "\(name): unavailable" }
        var text = "\(name): \(worst.label) \(worst.leftPercent)% left"
        switch UsageColor.verdict(worst, now: Date()) {
        case .fine: break
        case .tight: text += ", running low"
        case .out: text += ", running out"
        }
        if !errors.isEmpty { text += ", an account couldn't be read" }
        return text
    }
}

/// One provider as a row: tiny meters and its fullest window while closed, a bar per window once open.
private struct PoolRows: View, Themed {
    let pool: ProviderPool
    let expanded: Bool
    let reduceMotion: Bool
    let toggle: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) var contrast

    private static let meterWidth: CGFloat = 16
    private static let meterHeight: CGFloat = 5

    /// A provider opens by itself only when a window is heading for trouble or an account failed.
    static func needsAttention(_ pool: ProviderPool) -> Bool {
        let now = Date()
        return !pool.errors.isEmpty || pool.windows.contains { UsageColor.verdict($0, now: now) != .fine }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    AgentIcon(id: pool.provider).padding(.trailing, 6)
                    // The plan gives way first when four meters leave no room for it.
                    ViewThatFits(in: .horizontal) {
                        if let plan = pool.plan {
                            HStack(spacing: 6) {
                                name
                                Text(plan).font(.system(size: 12)).foregroundStyle(palette.tertiaryText).lineLimit(1)
                            }
                        }
                        name
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(hovering ? palette.secondaryText : palette.tertiaryText)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    summary
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressDim())
            .onHover { hovering = $0 }
            .accessibilityLabel(pool.spokenSummary)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            Collapsible(expanded: expanded, reduceMotion: reduceMotion) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pool.windows) { PoolBar(window: $0, labelWidth: labelWidth) }
                    ForEach(pool.errors, id: \.self) { error in
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card))
                .padding(.top, 8)
            }
        }
    }

    /// As wide as the card's longest window name, so its bars line up and short names leave them room.
    private var labelWidth: CGFloat {
        let widths = pool.windows.map { ($0.label as NSString).size(withAttributes: [.font: PoolBar.labelFont]).width }
        return min(140, (widths.max() ?? 0).rounded(.up))
    }

    private var name: some View {
        Text(pool.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
    }

    /// Closed, the row answers "is anything wrong"; open, the bars below do, so it names the account instead.
    @ViewBuilder
    private var summary: some View {
        if expanded {
            Text(pool.accounts.count == 1 ? pool.accounts[0].locations[0] : "\(pool.accounts.count) accounts")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .transition(.blurFade)
        } else {
            let now = Date()
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(pool.windows) { window in
                        Capsule().fill(palette.track)
                            .overlay(alignment: .leading) {
                                if window.leftPercent > 0 {
                                    Capsule()
                                        .fill(UsageColor.verdict(window, now: now).color)
                                        .frame(width: max(Self.meterHeight, Self.meterWidth * CGFloat(window.leftPercent) / 100))
                                }
                            }
                            .frame(width: Self.meterWidth, height: Self.meterHeight)
                    }
                }
                if let worst = pool.fullest {
                    let verdict = UsageColor.verdict(worst, now: now)
                    Text("\(worst.leftPercent)%")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(verdict == .fine ? palette.secondaryText : verdict.color)
                        .frame(minWidth: 34, alignment: .trailing)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.orange)
                }
            }
            .transition(.blurFade)
        }
    }
}

private struct PoolBar: View, Themed {
    let window: ProviderPool.Window
    @Environment(\.colorSchemeContrast) var contrast

    let labelWidth: CGFloat

    static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let resetFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    /// Wide enough for the longest reset, so every bar in a card ends at the same place.
    private static let resetWidth = ("23h 59m" as NSString).size(withAttributes: [.font: resetFont]).width.rounded(.up)

    /// The bar never gets narrower than this; a longer name moves above its bar instead.
    private static let minBarWidth: CGFloat = 50

    /// One line of fixed columns: name, bar, what's left, time to reset. Only a window heading for
    /// trouble adds its outlook below; the tooltip and VoiceOver always get the whole sentence.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let verdict = UsageColor.verdict(window, now: now)
            let outlook = outlook(window.pace(now: now), now: now)
            let detail = detail(now: now)
            let name = Text(window.label).font(Font(Self.labelFont)).lineLimit(1)
            let bar = HStack(spacing: window.segments.count > 1 ? 3 : 0) {
                ForEach(Array(window.segments.enumerated()), id: \.offset) { _, segment in
                    Segment(window: segment, now: now)
                }
            }
            .frame(minWidth: Self.minBarWidth, idealWidth: Self.minBarWidth, maxWidth: .infinity)
            .frame(height: 5)
            let left = Text("\(window.leftPercent)%")
                .font(.system(size: 12).monospacedDigit())
                .ticking(window.leftPercent)
                .frame(minWidth: 34, alignment: .trailing)
            let reset = Text(window.resetsAt.map { compact(until: $0, now: now) } ?? "")
                .font(Font(Self.resetFont))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
                .frame(width: Self.resetWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        name.frame(width: labelWidth, alignment: .leading)
                        bar
                        left
                        reset
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        name
                        HStack(spacing: 8) {
                            bar
                            left
                            reset
                        }
                    }
                }
                if verdict != .fine, let outlook {
                    Text(outlook)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(verdict.color)
                        .lineLimit(1)
                }
            }
            .help(detail)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([window.label, "\(window.leftPercent)% left", detail].filter { !$0.isEmpty }
                .joined(separator: ", "))
        }
        .settling(window.usedPercent)
    }

    /// One account's share of the bar: what's left. Any share above zero shows at least a full dot,
    /// and only a bar that's heading for trouble gets the even-pace mark, so a calm row stays calm.
    private struct Segment: View, Themed {
        let window: UsageWindow?
        let now: Date
        @Environment(\.colorSchemeContrast) var contrast

        private static let tickWidth: CGFloat = 2
        private static let tickOverhang: CGFloat = 4

        var body: some View {
            GeometryReader { geo in
                let verdict = window.map { UsageColor.verdict($0, now: now) }
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track).opacity(window == nil ? 0.5 : 1)
                    if let window, let verdict, window.leftPercent > 0 {
                        Capsule()
                            .fill(verdict.color)
                            .frame(width: max(geo.size.height, geo.size.width * window.leftPercent / 100))
                    }
                }
                .overlay(alignment: .leading) {
                    if let window, let verdict, verdict != .fine, window.leftPercent > 0,
                       let pace = window.pace(now: now) {
                        let centered = geo.size.width * (1 - pace.elapsed) - Self.tickWidth / 2
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.55))
                            .frame(width: Self.tickWidth, height: geo.size.height + Self.tickOverhang)
                            .offset(x: min(max(centered, 0), geo.size.width - Self.tickWidth))
                    }
                }
            }
        }
    }

    /// Where the window lands at the current rate; silent while it's too young to say.
    private func outlook(_ pace: UsageWindow.Pace?, now: Date) -> String? {
        let spent = window.segments.filter { $0.map { $0.leftPercent.rounded() <= 0 } ?? false }.count
        if spent > 0 {
            return window.segments.count > 1 ? "\(spent) of \(window.segments.count) at limit" : "Limit reached"
        }
        guard let pace else { return nil }
        if let runsOut = pace.runsOutAt { return "Runs out \(countdown(to: runsOut, now: now))" }
        return "~\(max(1, Int(pace.projectedLeft.rounded())))% left at reset"
    }

    /// "Runs out in 40m · resets in 1h 17m", or whichever half is known.
    private func detail(now: Date) -> String {
        let reset = window.resetsAt.map { "resets \(countdown(to: $0, now: now))" }
        guard let outlook = outlook(window.pace(now: now), now: now) else {
            return reset.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
        }
        return [outlook, reset].compactMap { $0 }.joined(separator: " · ")
    }

    private func countdown(to date: Date, now: Date) -> String {
        let text = compact(until: date, now: now)
        return text == "now" ? text : "in \(text)"
    }

    /// "40m", "1h 17m" or "3d 14h": the same time as the sentence, short enough for a column.
    private func compact(until date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes / (24 * 60))d \(minutes % (24 * 60) / 60)h"
    }
}

private struct AgentIcon: View, Themed {
    let id: String
    var size: CGFloat = 22
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 6 / 22, style: .continuous).fill(palette.fill)
            if let logo = Self.logo(for: id) {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 16 / 22, height: size * 16 / 22)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: size / 2, weight: .semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 6 / 22, style: .continuous).strokeBorder(palette.hairline, lineWidth: 0.5))
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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .opacity(isEnabled ? 1 : 0.45)
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
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
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
/// the window comes on or off screen, which SwiftUI's `onAppear` doesn't promise for a menu bar extra.
private struct MenuWindow: NSViewRepresentable {
    let onVisibility: (Bool) -> Void

    func makeNSView(context: Context) -> WatchingView {
        let view = WatchingView()
        view.onVisibility = onVisibility
        return view
    }

    func updateNSView(_ nsView: WatchingView, context: Context) {
        nsView.onVisibility = onVisibility
    }

    final class WatchingView: NSView {
        var onVisibility: (Bool) -> Void = { _ in }
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
                    guard let self else { return }
                    self.onVisibility(self.window?.occlusionState.contains(.visible) == true)
                }
            }
            if window.occlusionState.contains(.visible) { onVisibility(true) }
        }
    }
}

// MARK: - Transitions

private struct BlurFade: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.opacity(active ? 0 : 1).blur(radius: active && !reduceMotion ? 2 : 0)
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
