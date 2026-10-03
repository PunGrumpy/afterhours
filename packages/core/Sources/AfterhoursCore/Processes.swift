import Darwin
import Foundation

/// Minimal libproc/sysctl wrappers shared by the app and the hook binary.
public enum Proc {
    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func allPids() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(max(n, 0)))).filter { $0 > 0 }
    }

    /// Short process name (up to 32 chars, not truncated to 16 like p_comm).
    public static func name(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buf, UInt32(buf.count))
        guard length > 0 else { return nil }
        return String(decoding: buf.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Absolute path of the executable, with symlinks resolved.
    public static func executablePath(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard length > 0 else { return nil }
        return String(decoding: buf.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func parent(_ pid: Int32) -> Int32? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbsi_ppid)
    }

    /// Total CPU time (user + system) in nanoseconds.
    public static func cpuNanos(_ pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        let ticks = info.pti_total_user + info.pti_total_system
        return ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    /// When the process started, or nil if it's gone.
    public static func startTime(_ pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// CPU used since the last scan; a process that ran before that scan without a sample only sets its baseline.
    public static func cpuSinceLastScan(current: UInt64, previous: UInt64?, startedAt: Date?, lastScan: Date?) -> UInt64 {
        if let previous { return current > previous ? current - previous : 0 }
        guard let lastScan, let startedAt, startedAt >= lastScan else { return 0 }
        return current
    }

    /// argv of a process (requires same user; fails silently otherwise).
    public static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }

        let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }  // exec path
        while i < size, buf[i] == 0 { i += 1 }  // padding

        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()
}
