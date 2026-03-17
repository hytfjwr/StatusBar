import Darwin.Mach
import Foundation

@MainActor
final class SystemMonitorService {
    private struct CPUTicks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
    }

    private var previousCPUTicks = CPUTicks()

    func cpuUsage() -> Double {
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

        return Double(deltaUser + deltaSystem + deltaNice) / Double(totalDelta)
    }

    func memoryUsage() -> Double {
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

        return Double(active + wired + compressed) / Double(totalMemory)
    }
}
