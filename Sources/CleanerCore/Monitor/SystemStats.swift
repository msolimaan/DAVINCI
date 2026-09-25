import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct CPUSnapshot: Sendable {
    public let usage: Double
    public let user: Double
    public let system: Double

    public static let zero = CPUSnapshot(usage: 0, user: 0, system: 0)
}

public enum MemoryPressure: Sendable {
    case normal, warning, critical

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "High"
        }
    }
}

public struct MemorySnapshot: Sendable {
    public let total: UInt64
    public let used: UInt64
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let pressure: MemoryPressure

    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct DiskSnapshot: Sendable {
    public let total: Int64
    public let available: Int64

    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct ProcessUsage: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let memoryBytes: UInt64
    public let cpuPercent: Double
}

public enum SystemStats {
    public static func disk(at url: URL = URL(fileURLWithPath: "/")) -> DiskSnapshot? {
        #if os(macOS)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSnapshot(total: Int64(total), available: available)
        #else
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else { return nil }
        return DiskSnapshot(total: Int64(total), available: Int64(available))
        #endif
    }

    public static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Processes using the most memory, from `ps` (only fields any user may read).
    public static func topProcesses(limit: Int = 6) async -> [ProcessUsage] {
        let result = await CommandRunner.run("/bin/ps -Aco pid=,pcpu=,rss=,comm= -m")
        return Array(parseProcessList(result.output).prefix(limit))
    }

    static func parseProcessList(_ output: String) -> [ProcessUsage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")),
                  let rssKilobytes = UInt64(fields[2]) else { return nil }
            return ProcessUsage(
                id: pid,
                name: String(fields[3]).trimmingCharacters(in: .whitespaces),
                memoryBytes: rssKilobytes * 1024,
                cpuPercent: cpu
            )
        }
        .sorted { $0.memoryBytes > $1.memoryBytes }
    }
}

#if canImport(Darwin)
extension SystemStats {
    /// Memory usage computed the way Activity Monitor does ("App Memory + Wired + Compressed").
    public static func memory() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(getpagesize())
        let internal = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internal > purgeable ? internal - purgeable : 0) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.external_page_count) + purgeable) * page
        let total = ProcessInfo.processInfo.physicalMemory

        return MemorySnapshot(
            total: total,
            used: min(total, app + wired + compressed),
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            pressure: memoryPressure()
        )
    }

    static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

/// Measures CPU load between two calls, the way `top` does.
public final class CPUSampler: @unchecked Sendable {
    private var previous: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private let lock = NSLock()

    public init() {}

    public func sample() -> CPUSnapshot {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .zero }

        // cpu_ticks is (user, system, idle, nice).
        let ticks = info.cpu_ticks
        let current = (user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)

        lock.lock()
        defer { lock.unlock() }
        defer { previous = current }
        guard let last = previous else { return .zero }

        let user = Double(current.user &- last.user) + Double(current.nice &- last.nice)
        let system = Double(current.system &- last.system)
        let idle = Double(current.idle &- last.idle)
        let total = user + system + idle
        guard total > 0 else { return .zero }
        return CPUSnapshot(usage: (user + system) / total, user: user / total, system: system / total)
    }
}
#endif
