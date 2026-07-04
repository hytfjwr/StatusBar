import Darwin
import Foundation

@MainActor
final class NetworkService {
    private var previousBytes: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTime: Date?

    struct InterfaceSpeed: Equatable {
        let name: String
        let download: Double // bytes/sec
        let upload: Double // bytes/sec
    }

    struct NetworkSnapshot: Equatable {
        let download: Double // total bytes/sec
        let upload: Double // total bytes/sec
        let interfaces: [InterfaceSpeed]

        var downloadFormatted: String {
            Self.formatSpeed(download)
        }

        var uploadFormatted: String {
            Self.formatSpeed(upload)
        }

        static func formatSpeed(_ bytesPerSec: Double) -> String {
            let kbps = bytesPerSec / 1_024
            if kbps > 999 {
                return String(format: "%.1f MB/s", kbps / 1_024)
            }
            return String(format: "%.0f kB/s", kbps)
        }
    }

    func poll() -> NetworkSnapshot {
        let current = getNetworkBytes()
        let now = Date()

        defer {
            previousBytes = current
            previousTime = now
        }

        guard let prevTime = previousTime else {
            return NetworkSnapshot(download: 0, upload: 0, interfaces: [])
        }

        let elapsed = now.timeIntervalSince(prevTime)
        let interfaces = Self.computeInterfaceSpeeds(previous: previousBytes, current: current, elapsed: elapsed)

        return NetworkSnapshot(
            download: interfaces.map(\.download).reduce(0, +),
            upload: interfaces.map(\.upload).reduce(0, +),
            interfaces: interfaces
        )
    }

    /// Computes per-interface speeds from two byte-count snapshots. Pure function for testability.
    /// Interfaces present only in `previous` are ignored; interfaces new in `current` are included
    /// with 0/0 speeds. A counter that appears to have reset (current < previous) reports 0 for
    /// that direction. Results are sorted by interface name.
    nonisolated static func computeInterfaceSpeeds(
        previous: [String: (rx: UInt64, tx: UInt64)],
        current: [String: (rx: UInt64, tx: UInt64)],
        elapsed: TimeInterval
    ) -> [InterfaceSpeed] {
        guard elapsed > 0 else {
            return []
        }

        return current.keys.sorted().map { name in
            guard let prev = previous[name] else {
                // First sample for this interface — no baseline to diff against.
                return InterfaceSpeed(name: name, download: 0, upload: 0)
            }
            let curr = current[name] ?? (rx: 0, tx: 0)
            let deltaRx = curr.rx >= prev.rx ? Double(curr.rx - prev.rx) : 0
            let deltaTx = curr.tx >= prev.tx ? Double(curr.tx - prev.tx) : 0
            return InterfaceSpeed(name: name, download: deltaRx / elapsed, upload: deltaTx / elapsed)
        }
    }

    /// IPv4 addresses of active non-loopback interfaces, ordered en* first.
    nonisolated static func localIPv4Addresses() -> [(name: String, address: String)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var seen = Set<String>()
        var results: [(name: String, address: String)] = []

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            let name = String(cString: addr.pointee.ifa_name)
            guard !name.hasPrefix("lo"),
                  !seen.contains(name),
                  let sockaddrPtr = addr.pointee.ifa_addr,
                  sockaddrPtr.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            var sinAddr = UnsafeRawPointer(sockaddrPtr).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &sinAddr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }

            let length = buffer.firstIndex(of: 0) ?? buffer.count
            guard let address = String(
                bytes: buffer[0 ..< length].map { UInt8(bitPattern: $0) }, encoding: .utf8
            ) else {
                continue
            }

            seen.insert(name)
            results.append((name: name, address: address))
        }

        return results.sorted { lhs, rhs in
            let lhsRank = interfaceRank(lhs.name)
            let rhsRank = interfaceRank(rhs.name)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name < rhs.name
        }
    }

    nonisolated private static func interfaceRank(_ name: String) -> Int {
        if name.hasPrefix("en") {
            return 0
        }
        if name.hasPrefix("utun") {
            return 1
        }
        return 2
    }

    private func getNetworkBytes() -> [String: (rx: UInt64, tx: UInt64)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return [:]
        }
        defer { freeifaddrs(ifaddr) }

        var result: [String: (rx: UInt64, tx: UInt64)] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)
            // getifaddrs returns multiple entries per interface (AF_LINK, AF_INET, AF_INET6).
            // Only AF_LINK entries have ifa_data laid out as if_data.
            // Without checking family here, ifa_data from AF_INET etc. would be reinterpreted
            // as if_data and add bogus byte counts.
            let family = addr.pointee.ifa_addr?.pointee.sa_family
            if name.hasPrefix("en") || name.hasPrefix("utun"),
               family == UInt8(AF_LINK),
               let data = addr.pointee.ifa_data
            {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                result[name] = (rx: UInt64(networkData.ifi_ibytes), tx: UInt64(networkData.ifi_obytes))
            }
            cursor = addr.pointee.ifa_next
        }

        return result
    }
}
