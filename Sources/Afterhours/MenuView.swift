import AfterhoursCore
import AppKit
import SwiftUI

private enum Palette {
    static let background = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255).opacity(0.82)
    static let blue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let green = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let divider = Color.white.opacity(0.1)
    static let fill = Color.white.opacity(0.1)
}

/// Motion tokens. Every animation in the menu uses one of these three, so the menu moves as one
/// system. Hover and hotkey changes are deliberately instant.
private enum Motion {
    /// Press feedback: a strong ease-out, so the scale starts moving on the first frame.
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    /// State changes (row fades, status text, errors).
    static let fade = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    /// The switch knob moves on screen and can be flipped again mid-flight, so it's a spring.
    static let knob = Animation.spring(duration: 0.25, bounce: 0)
}

struct MenuView: View {
    let model: AppModel
    @Bindable var prefs: Preferences
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

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
            divider
            BatterySection(battery: model.battery, prefs: prefs)
            divider
            agents
            divider
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
        .background(Palette.background)
        .background(DarkWindow())
        .animation(Motion.fade, value: model.lastError)
    }

    private var divider: some View {
        Rectangle().fill(Palette.divider).frame(height: 1).padding(.horizontal, 16)
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
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        // Keyed by state, not by the ticking minutes, so only real state changes cross-fade.
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
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            if summaries.isEmpty {
                Text("No coding agents found")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                VStack(spacing: 8) {
                    ForEach(summaries) { AgentRow(summary: $0) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

/// The mug mascot, in the header. Its steam and face carry the state; the blue fill matches the switch
/// while it keeps the Mac awake.
private struct MascotBadge: View {
    let state: HoldState

    var body: some View {
        let mood = Mug.Mood(state)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(state.isHolding ? Palette.blue : Palette.fill)
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

private struct BatterySection: View {
    let battery: BatteryStatus
    let prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Battery")
            if let percent = battery.percent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        // Width follows the charge with no animation: it updates every few seconds.
                        Capsule().fill(color(percent)).frame(width: geo.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 7)
                .padding(.top, 10)
                HStack {
                    Text(battery.charging ? "\(percent)%, charging" : battery.onAC ? "\(percent)%, plugged in" : "\(percent)% left")
                        .fontWeight(.medium)
                    Spacer()
                    Text(cutoff).foregroundStyle(.white.opacity(0.45))
                }
                .font(.system(size: 12.5).monospacedDigit())
                .padding(.top, 8)
            } else {
                Text("On AC power")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
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

private struct AgentRow: View {
    let summary: AgentSummary

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(id: summary.id)
            Text(summary.name)
                .font(.system(size: 13.5, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.working > 0 {
                status(summary.sessions == 1 ? "1 session" : "\(summary.sessions) sessions", dot: Palette.green)
            } else if summary.waiting > 0 {
                status("Needs you", dot: Palette.orange)
            } else {
                Text("Idle").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.4))
            }
        }
        // Idle agents recede by opacity alone, so the change reads without movement.
        .opacity(isActive ? 1 : 0.45)
        .animation(Motion.fade, value: isActive)
        .accessibilityElement(children: .combine)
    }

    private var isActive: Bool { summary.working + summary.waiting > 0 }

    private func status(_ text: String, dot: Color) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
            Circle().fill(dot).frame(width: 7, height: 7)
        }
    }
}

/// The agent's logo from the bundled `agents/<id>.png`, or a generic tile for agents without one.
private struct AgentIcon: View {
    let id: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Palette.fill)
            if let image = Self.image(for: id) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // A faint inset edge so dark logos keep their shape on the dark menu.
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private static var cache: [String: NSImage?] = [:]

    private static func image(for id: String) -> NSImage? {
        if let cached = cache[id] { return cached }
        let image = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "agents")
            .flatMap(NSImage.init(contentsOf:))
        cache[id] = image
        return image
    }
}

private struct ChipButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hovering ? 0.18 : 0.1)))
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }  // Instant on purpose: hover fires too often to animate.
    }
}

/// Scales a pressed control to 0.97 so the click registers before the action finishes.
private struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A row that behaves like a native menu item: the highlight follows the pointer with no transition.
private struct MenuItem: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 14))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(hovering ? 0.8 : 0.4))
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

/// 40×24 switch.
private struct PillSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillSwitchBody(isOn: configuration.$isOn)
    }
}

private struct PillSwitchBody: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? Palette.blue : Color.white.opacity(0.2))
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

/// Forces the hosting window (the menu bar popover) into dark vibrancy to match the design.
private struct DarkWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.appearance = NSAppearance(named: .darkAqua) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Transitions

private struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.opacity(active ? 0 : 1).blur(radius: active ? 2 : 0)
    }
}

private extension AnyTransition {
    /// Cross-fade with a 2 pt blur, so two states read as one changing element instead of two
    /// overlapping ones.
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

private extension HoldState {
    /// Identity for transitions: changes when the state changes, not when its payload ticks.
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
