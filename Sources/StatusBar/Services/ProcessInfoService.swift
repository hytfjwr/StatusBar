import Foundation
import StatusBarKit

// MARK: - ProcessInfoService

/// Top-process lookup backed by `ps`. Intended for on-demand popup display
/// only — never poll this in the background.
enum ProcessInfoService {
    struct ProcessSample: Equatable, Identifiable {
        let pid: Int
        let name: String
        let cpuPercent: Double
        let residentBytes: UInt64
        var id: Int {
            pid
        }
    }

    enum SortKey {
        case cpu
        case memory
    }

    /// Runs `ps` and returns the top rows sorted by the given key. Returns `[]` on failure.
    /// The list is capped with `head`: ShellCommand drains stdout only after the child
    /// exits, so an uncapped full process list (>64KB) fills the pipe buffer and
    /// deadlocks until the timeout kills the child.
    static func sample(sortedBy key: SortKey) async -> [ProcessSample] {
        let sortFlag = key == .cpu ? "-r" : "-m"
        let command = "ps -Aeo pid=,pcpu=,rss=,comm= \(sortFlag) | head -n 40"
        guard let output = try? await ShellCommand.run(command, timeout: 3) else {
            return []
        }
        return parsePSOutput(output)
    }

    /// Parses `ps -Areo pid=,pcpu=,rss=,comm=` output. Pure function for testability.
    nonisolated static func parsePSOutput(_ output: String) -> [ProcessSample] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let cpuPercent = Double(parts[1]),
                  let rssKB = UInt64(parts[2])
            else {
                return nil
            }
            let comm = String(parts[3])
            let name = URL(fileURLWithPath: comm).lastPathComponent
            return ProcessSample(pid: pid, name: name, cpuPercent: cpuPercent, residentBytes: rssKB * 1_024)
        }
    }

    nonisolated static func topByCPU(_ samples: [ProcessSample], limit: Int = 5) -> [ProcessSample] {
        samples.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit).map(\.self)
    }

    nonisolated static func topByMemory(_ samples: [ProcessSample], limit: Int = 5) -> [ProcessSample] {
        samples.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit).map(\.self)
    }
}
