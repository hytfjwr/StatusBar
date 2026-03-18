import Foundation

final class DiskService: @unchecked Sendable {
    struct DiskSnapshot {
        let totalBytes: Int64
        let freeBytes: Int64

        var usedBytes: Int64 {
            totalBytes - freeBytes
        }

        var usedFraction: Double {
            guard totalBytes > 0 else {
                return 0
            }
            return Double(usedBytes) / Double(totalBytes)
        }

        var usedPercent: Int {
            Int(usedFraction * 100)
        }

        var usedFormatted: String {
            Self.formatBytes(usedBytes)
        }

        var totalFormatted: String {
            Self.formatBytes(totalBytes)
        }

        var freeFormatted: String {
            Self.formatBytes(freeBytes)
        }

        private static func formatBytes(_ bytes: Int64) -> String {
            let gb = Double(bytes) / 1_073_741_824
            if gb >= 1 {
                return String(format: "%.0f GB", gb)
            }
            let mb = Double(bytes) / 1_048_576
            return String(format: "%.0f MB", mb)
        }
    }

    func poll() -> DiskSnapshot {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        let total = (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return DiskSnapshot(totalBytes: total, freeBytes: free)
    }
}
