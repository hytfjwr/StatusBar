import Darwin
import Foundation

@MainActor
final class NetworkService {
    private var previousRx: UInt64 = 0
    private var previousTx: UInt64 = 0
    private var previousTime: Date?

    struct NetworkSpeed {
        let download: Double // bytes/sec
        let upload: Double // bytes/sec

        var downloadFormatted: String {
            Self.formatSpeed(download)
        }

        var uploadFormatted: String {
            Self.formatSpeed(upload)
        }

        private static func formatSpeed(_ bytesPerSec: Double) -> String {
            let kbps = bytesPerSec / 1_024
            if kbps > 999 {
                return String(format: "%.1f MB/s", kbps / 1_024)
            }
            return String(format: "%.0f kB/s", kbps)
        }
    }

    func poll() -> NetworkSpeed {
        let (rx, tx) = getNetworkBytes()
        let now = Date()

        defer {
            previousRx = rx
            previousTx = tx
            previousTime = now
        }

        guard let prevTime = previousTime else {
            return NetworkSpeed(download: 0, upload: 0)
        }

        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed > 0 else {
            return NetworkSpeed(download: 0, upload: 0)
        }

        let deltaRx = rx >= previousRx ? Double(rx - previousRx) : 0
        let deltaTx = tx >= previousTx ? Double(tx - previousTx) : 0

        return NetworkSpeed(
            download: deltaRx / elapsed,
            upload: deltaTx / elapsed
        )
    }

    private func getNetworkBytes() -> (rx: UInt64, tx: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("utun") {
                if let data = addr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalRx += UInt64(networkData.ifi_ibytes)
                    totalTx += UInt64(networkData.ifi_obytes)
                }
            }
            cursor = addr.pointee.ifa_next
        }

        return (totalRx, totalTx)
    }
}
