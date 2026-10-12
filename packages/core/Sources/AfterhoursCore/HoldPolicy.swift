import Foundation

/// Why Afterhours holds the Mac awake, either because an agent is working or because it's waiting for your reply.
public enum HoldReason: Equatable, Sendable {
    case working
    /// A nil `until` waits until every session closes.
    case waitingForYou(until: Date?)
}

public enum HoldState: Equatable, Sendable {
    case disabled
    case paused(until: Date)
    case holding
    case blocked(String)  // agents are working, but a safety rule says no
    case idle

    public var isHolding: Bool { self == .holding }
}

/// The rules that decide whether to keep the Mac awake, free of IOKit and timers so tests can pin them.
public enum HoldPolicy {
    /// The wait setting that lasts until every agent session closes.
    public static let untilSessionsClose = -1

    /// Now while an agent works, kept while sessions stay open, and forgotten once none are left.
    public static func lastWorkingAt(previous: Date?, working: Bool, hasSessions: Bool, now: Date) -> Date? {
        if working { return now }
        return hasSessions ? previous : nil
    }

    /// Holds while an agent works, then waits for your reply for as long as the power source's setting allows.
    public static func reason(working: Bool, hasSessions: Bool, lastWorkingAt: Date?, onAC: Bool,
                              pluggedInWaitMinutes: Int, batteryWaitMinutes: Int, now: Date) -> HoldReason? {
        if working { return .working }
        guard let lastWorkingAt, hasSessions else { return nil }
        let minutes = onAC ? pluggedInWaitMinutes : batteryWaitMinutes
        if minutes == untilSessionsClose { return .waitingForYou(until: nil) }
        let until = lastWorkingAt.addingTimeInterval(TimeInterval(minutes * 60))
        return until > now ? .waitingForYou(until: until) : nil
    }

    /// The safety rule that stops a hold, if one applies.
    public static func blocker(thermalCritical: Bool, lowPowerMode: Bool, respectLowPowerMode: Bool, onAC: Bool,
                               onlyWhenPluggedIn: Bool, batteryPercent: Int?, batteryThreshold: Int) -> String? {
        if thermalCritical { return "Your Mac is too hot" }
        if respectLowPowerMode, lowPowerMode { return "Low Power Mode is on" }
        guard !onAC else { return nil }
        if onlyWhenPluggedIn { return "Your Mac isn't plugged in" }
        if let batteryPercent, batteryThreshold > 0, batteryPercent < batteryThreshold {
            return "Battery is below \(batteryThreshold)%"
        }
        return nil
    }

    /// Minutes of battery before the cutoff releases the hold, scaling macOS's time-to-empty by the share above it.
    public static func minutesUntilCutoff(batteryPercent: Int, batteryThreshold: Int, minutesToEmpty: Int) -> Int? {
        guard minutesToEmpty > 0, batteryPercent > 0 else { return nil }
        let floor = min(max(batteryThreshold, 0), 100)
        guard batteryPercent > floor else { return 0 }
        return minutesToEmpty * (batteryPercent - floor) / batteryPercent
    }

    /// Off beats paused, paused beats the rest, nothing to hold for is idle, and a safety rule beats a hold.
    public static func state(enabled: Bool, pausedUntil: Date?, reason: HoldReason?, blocker: String?) -> HoldState {
        if !enabled { return .disabled }
        if let pausedUntil { return .paused(until: pausedUntil) }
        guard reason != nil else { return .idle }
        if let blocker { return .blocked(blocker) }
        return .holding
    }
}
