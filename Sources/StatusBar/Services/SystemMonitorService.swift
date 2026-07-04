import Darwin.Mach
import Foundation

@MainActor
final class SystemMonitorService {
    static let shared = SystemMonitorService()
    private struct CPUTicks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
    }

    private var previousCPUTicks = CPUTicks()
    private var cachedCPU: Double = 0
    private var cachedMemory: Double = 0
    private var lastCPUUpdate: Date = .distantPast
    private var lastMemoryUpdate: Date = .distantPast

    /// Per-core ticks (user, system, idle, nice) from the previous sample.
    private var previousCoreTicks: [[UInt64]] = []
    private var cachedPerCore: [Double] = []
    private var lastPerCoreUpdate: Date = .distantPast

    /// Minimum interval between actual kernel calls. Callers within this
    /// window receive the cached value, avoiding stale-delta problems when
    /// multiple consumers poll at different rates.
    private let cacheWindow: TimeInterval = 0.5

    private init() {}

    func cpuUsage() -> Double {
        let now = Date()
        if now.timeIntervalSince(lastCPUUpdate) < cacheWindow {
            return cachedCPU
        }
        lastCPUUpdate = now

        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        let user = UInt64(loadInfo.cpu_ticks.0) // USER
        let system = UInt64(loadInfo.cpu_ticks.1) // SYSTEM
        let idle = UInt64(loadInfo.cpu_ticks.2) // IDLE
        let nice = UInt64(loadInfo.cpu_ticks.3) // NICE

        let deltaUser = user - previousCPUTicks.user
        let deltaSystem = system - previousCPUTicks.system
        let deltaIdle = idle - previousCPUTicks.idle
        let deltaNice = nice - previousCPUTicks.nice

        previousCPUTicks = CPUTicks(user: user, system: system, idle: idle, nice: nice)

        let totalDelta = deltaUser + deltaSystem + deltaIdle + deltaNice
        guard totalDelta > 0 else {
            return 0
        }

        cachedCPU = Double(deltaUser + deltaSystem + deltaNice) / Double(totalDelta)
        return cachedCPU
    }

    func memoryUsage() -> Double {
        let now = Date()
        if now.timeIntervalSince(lastMemoryUpdate) < cacheWindow {
            return cachedMemory
        }
        lastMemoryUpdate = now

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        guard totalMemory > 0 else {
            return 0
        }

        cachedMemory = Double(active + wired + compressed) / Double(totalMemory)
        return cachedMemory
    }

    // MARK: - Memory Snapshot

    struct MemorySnapshot: Equatable {
        let totalBytes: UInt64
        let appBytes: UInt64 // active pages
        let wiredBytes: UInt64
        let compressedBytes: UInt64
        let swapUsedBytes: UInt64
        let swapTotalBytes: UInt64

        var usedBytes: UInt64 {
            appBytes + wiredBytes + compressedBytes
        }

        var usedFraction: Double {
            totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
        }
    }

    /// Detailed memory breakdown (app / wired / compressed / swap). Uncached —
    /// intended for on-demand popup display, not high-frequency polling.
    func memorySnapshot() -> MemorySnapshot {
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let (swapUsed, swapTotal) = swapUsage()

        guard result == KERN_SUCCESS else {
            return MemorySnapshot(
                totalBytes: totalMemory,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                swapUsedBytes: swapUsed,
                swapTotalBytes: swapTotal
            )
        }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return MemorySnapshot(
            totalBytes: totalMemory,
            appBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal
        )
    }

    private func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = withUnsafeMutablePointer(to: &usage) {
            sysctlbyname("vm.swapusage", $0, &size, nil, 0)
        }
        guard result == 0 else {
            return (0, 0)
        }
        return (usage.xsu_used, usage.xsu_total)
    }

    // MARK: - Per-core CPU Usage

    /// Per-core CPU usage in [0, 1], ordered by core index.
    /// First call returns zeros (no previous sample). Cached for `cacheWindow`.
    func perCoreUsage() -> [Double] {
        let now = Date()
        if now.timeIntervalSince(lastPerCoreUpdate) < cacheWindow {
            return cachedPerCore
        }
        lastPerCoreUpdate = now

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount
        )

        guard result == KERN_SUCCESS, let info else {
            previousCoreTicks = []
            cachedPerCore = []
            return cachedPerCore
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)
            )
        }

        let cores = Int(cpuCount)
        var currentTicks: [[UInt64]] = []
        currentTicks.reserveCapacity(cores)
        for core in 0 ..< cores {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            currentTicks.append([user, system, idle, nice])
        }

        guard previousCoreTicks.count == cores else {
            previousCoreTicks = currentTicks
            cachedPerCore = Array(repeating: 0, count: cores)
            return cachedPerCore
        }

        var usages: [Double] = []
        usages.reserveCapacity(cores)
        for core in 0 ..< cores {
            let prev = previousCoreTicks[core]
            let curr = currentTicks[core]
            let deltaUser = curr[0] >= prev[0] ? curr[0] - prev[0] : 0
            let deltaSystem = curr[1] >= prev[1] ? curr[1] - prev[1] : 0
            let deltaIdle = curr[2] >= prev[2] ? curr[2] - prev[2] : 0
            let deltaNice = curr[3] >= prev[3] ? curr[3] - prev[3] : 0
            let total = deltaUser + deltaSystem + deltaIdle + deltaNice
            usages.append(total > 0 ? Double(deltaUser + deltaSystem + deltaNice) / Double(total) : 0)
        }

        previousCoreTicks = currentTicks
        cachedPerCore = usages
        return cachedPerCore
    }
}
