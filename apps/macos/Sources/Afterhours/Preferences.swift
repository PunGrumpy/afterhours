import Foundation
import Observation

@Observable
final class Preferences {
    var enabled: Bool { didSet { save(enabled, "enabled") } }
    /// 0 disables the cutoff.
    var batteryThreshold: Int { didSet { save(batteryThreshold, "batteryThreshold") } }
    var onlyWhenPluggedIn: Bool { didSet { save(onlyWhenPluggedIn, "onlyWhenPluggedIn") } }
    var respectLowPowerMode: Bool { didSet { save(respectLowPowerMode, "respectLowPowerMode") } }
    var lidClosedMode: Bool { didSet { save(lidClosedMode, "lidClosedMode") } }
    /// Minutes to wait for your reply after agents finish. 0 doesn't wait.
    var pluggedInWaitMinutes: Int { didSet { save(pluggedInWaitMinutes, "pluggedInWaitMinutes") } }
    /// Always finite, so a forgotten session can't drain the battery.
    var batteryWaitMinutes: Int { didSet { save(batteryWaitMinutes, "batteryWaitMinutes") } }

    static let untilSessionsClose = -1
    var turnDisplayOff: Bool { didSet { save(turnDisplayOff, "turnDisplayOff") } }
    var notifications: Bool { didSet { save(notifications, "notifications") } }
    /// A name from /System/Library/Sounds, or "" for none.
    var sound: String { didSet { save(sound, "sound") } }
    /// Stores opt-outs rather than opt-ins, so agents added later are detected by default.
    var disabledAgents: Set<String> { didSet { save(Array(disabledAgents).sorted(), "disabledAgents") } }

    var detectedAgents: Set<String> { Set(AgentKind.all.map(\.id)).subtracting(disabledAgents) }

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "enabled": true,
            "batteryThreshold": 15,
            "onlyWhenPluggedIn": false,
            "respectLowPowerMode": true,
            "lidClosedMode": true,
            "pluggedInWaitMinutes": Self.untilSessionsClose,
            "batteryWaitMinutes": 60,
            "turnDisplayOff": false,
            "notifications": true,
            "sound": "Glass",
        ])
        enabled = defaults.bool(forKey: "enabled")
        batteryThreshold = defaults.integer(forKey: "batteryThreshold")
        onlyWhenPluggedIn = defaults.bool(forKey: "onlyWhenPluggedIn")
        respectLowPowerMode = defaults.bool(forKey: "respectLowPowerMode")
        lidClosedMode = defaults.bool(forKey: "lidClosedMode")
        pluggedInWaitMinutes = defaults.integer(forKey: "pluggedInWaitMinutes")
        batteryWaitMinutes = defaults.integer(forKey: "batteryWaitMinutes")
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
