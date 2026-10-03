import AfterhoursCore
import Foundation

/// Waits for Afterhours to exit, then turns `pmset disablesleep` off, because a crash or Force Quit skips its cleanup.
func runGuard(watching pid: Int32) -> Never {
    // A closed terminal or Ctrl-C reaches the app too; what this waits for is the app's exit, not its own.
    signal(SIGHUP, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    // The app ignores SIGTERM to handle it itself, and that can carry over to a child; stay killable.
    signal(SIGTERM, SIG_DFL)
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { reenableSleep(after: pid) } }
    source.resume()
    // A process that's already gone sends no exit event.
    if !Proc.isAlive(pid) { reenableSleep(after: pid) }
    dispatchMain()
}

private func reenableSleep(after pid: Int32) {
    // Another Afterhours that's still running owns the setting now.
    let others = Proc.allPids().filter { $0 != pid && $0 != getpid() && Proc.name($0) == "Afterhours" }
    if others.isEmpty {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil { process.waitUntilExit() }
    }
    exit(0)
}
