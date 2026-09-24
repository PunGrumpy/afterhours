import Foundation
import Observation

/// User settings, persisted in UserDefaults.
@Observable
final class Preferences {
    var enabled: Bool { didSet { save(enabled, "enabled") } }
    /// Stop holding below this battery percentage when on battery. 0 disables the cutoff.
    var batteryThreshold: Int { didSet { save(batteryThreshold, "batteryThreshold") } }
    var onlyWhenPluggedIn: Bool { didSet { save(onlyWhenPluggedIn, "onlyWhenPluggedIn") } }
    var respectLowPowerMode: Bool { didSet { save(respectLowPowerMode, "respectLowPowerMode") } }
    /// Use `pmset disablesleep` so the Mac also stays awake with the lid closed.
    var lidClosedMode: Bool { didSet { save(lidClosedMode, "lidClosedMode") } }
    /// Keep holding this long after the last agent goes idle, so back-to-back turns don't flap.
    var graceMinutes: Int { didSet { save(graceMinutes, "graceMinutes") } }
    var turnDisplayOff: Bool { didSet { save(turnDisplayOff, "turnDisplayOff") } }
    var notifications: Bool { didSet { save(notifications, "notifications") } }
    /// A name from /System/Library/Sounds, or "" for silence.
    var sound: String { didSet { save(sound, "sound") } }
    /// Agents the user turned process detection off for. Storing the opt-outs, not the opt-ins,
    /// means agents added in later versions are detected by default.
    var disabledAgents: Set<String> { didSet { save(Array(disabledAgents).sorted(), "disabledAgents") } }

    var detectedAgents: Set<String> { Set(AgentKind.all.map(\.id)).subtracting(disabledAgents) }

    /// Called after any setting changes, so the model can re-evaluate right away.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "enabled": true,
            "batteryThreshold": 15,
            "onlyWhenPluggedIn": false,
            "respectLowPowerMode": true,
            "lidClosedMode": true,
            "graceMinutes": 1,
            "turnDisplayOff": false,
            "notifications": true,
            "sound": "Glass",
        ])
        enabled = defaults.bool(forKey: "enabled")
        batteryThreshold = defaults.integer(forKey: "batteryThreshold")
        onlyWhenPluggedIn = defaults.bool(forKey: "onlyWhenPluggedIn")
        respectLowPowerMode = defaults.bool(forKey: "respectLowPowerMode")
        lidClosedMode = defaults.bool(forKey: "lidClosedMode")
        graceMinutes = defaults.integer(forKey: "graceMinutes")
        turnDisplayOff = defaults.bool(forKey: "turnDisplayOff")
        notifications = defaults.bool(forKey: "notifications")
        sound = defaults.string(forKey: "sound") ?? ""
        disabledAgents = Set(defaults.stringArray(forKey: "disabledAgents") ?? [])
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange()
    }

    static let sounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()
}
