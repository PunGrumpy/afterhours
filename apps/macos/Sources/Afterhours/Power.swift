import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

nonisolated struct BatteryStatus: Equatable {
    var percent: Int?  // nil on desktops
    var onAC: Bool
    var charging: Bool
}

nonisolated enum Power {
    static func battery() -> BatteryStatus {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providing = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        let onAC = providing == kIOPSACPowerValue
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return BatteryStatus(percent: current * 100 / max, onAC: onAC,
                                 charging: desc[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return BatteryStatus(percent: nil, onAC: true, charging: false)
    }

    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    static var lidClosed: Bool { rootDomainProperty("AppleClamshellState") as? Bool ?? false }

    /// Reflects `pmset disablesleep`.
    static var sleepDisabled: Bool { rootDomainProperty("SleepDisabled") as? Bool ?? false }

    private static func rootDomainProperty(_ key: String) -> Any? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }
    static func displaySleepNow() { run("/usr/bin/pmset", ["displaysleepnow"]) }
}

final class SleepAssertion {
    private var idle: IOPMAssertionID = 0
    private var system: IOPMAssertionID = 0

    /// `PreventSystemSleep` is deprecated but powerd still honors it on AC, keeping a closed Mac awake without root.
    func hold(reason: String, lidClosed: Bool) {
        create("PreventUserIdleSystemSleep", reason, &idle)
        if lidClosed { create("PreventSystemSleep", reason, &system) } else { release(&system) }
    }

    func release() {
        release(&idle)
        release(&system)
    }

    private func create(_ type: String, _ reason: String, _ id: inout IOPMAssertionID) {
        guard id == 0 else { return }
        IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
    }

    private func release(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
}

/// `pmset disablesleep` keeps a closed Mac awake but needs root, so a sudoers rule allows exactly
/// `pmset -a disablesleep 0` and `1` without a password.
enum LidControl {
    static let sudoersPath = "/etc/sudoers.d/afterhours"

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        Power.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]).status == 0
    }

    static func install() throws {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("afterhours.sudoers")
        try rule.write(to: tmp, atomically: true, encoding: .utf8)
        let shell = "/usr/sbin/visudo -cf '\(tmp.path)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp.path)' \(sudoersPath)"
        try runAsAdmin(shell)
    }

    static func uninstall() throws {
        setSleepDisabled(false)
        try runAsAdmin("/bin/rm -f \(sudoersPath)")
    }

    private static func runAsAdmin(_ shell: String) throws {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            throw NSError(domain: "Afterhours", code: 1, userInfo: [
                NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? "Admin command failed",
            ])
        }
    }
}
