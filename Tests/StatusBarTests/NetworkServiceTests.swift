import Foundation
@testable import StatusBar
import Testing

struct NetworkSpeedTests {

    // MARK: - formatSpeed

    @Test("Formats zero bytes as 0 kB/s")
    func zeroBytes() {
        #expect(NetworkService.NetworkSpeed.formatSpeed(0) == "0 kB/s")
    }

    @Test("Formats sub-kilobyte speeds as kB/s")
    func subKilobyte() {
        // 512 bytes = 0.5 KB
        #expect(NetworkService.NetworkSpeed.formatSpeed(512) == "0 kB/s")
    }

    @Test("Formats kilobyte range as kB/s")
    func kilobyteRange() {
        // 100 KB = 102400 bytes
        let result = NetworkService.NetworkSpeed.formatSpeed(102_400)
        #expect(result == "100 kB/s")
    }

    @Test("Formats near-megabyte as kB/s")
    func nearMegabyte() {
        // 999 KB = 1023 * 1024 bytes → still kB/s
        let result = NetworkService.NetworkSpeed.formatSpeed(999 * 1_024)
        #expect(result == "999 kB/s")
    }

    @Test("Switches to MB/s above 999 kB/s")
    func megabyteRange() {
        // 1000 KB = 1000 * 1024 bytes → 1000 kB/s > 999 → MB/s
        let result = NetworkService.NetworkSpeed.formatSpeed(1_000 * 1_024)
        #expect(result.hasSuffix("MB/s"))
    }

    @Test("Formats multi-megabyte speeds")
    func multiMegabyte() {
        // 10 MB = 10 * 1024 * 1024 bytes
        let result = NetworkService.NetworkSpeed.formatSpeed(10 * 1_024 * 1_024)
        #expect(result == "10.0 MB/s")
    }

    // MARK: - NetworkSpeed properties

    @Test("downloadFormatted uses formatSpeed")
    func downloadFormatted() {
        let speed = NetworkService.NetworkSpeed(download: 102_400, upload: 0)
        #expect(speed.downloadFormatted == "100 kB/s")
    }

    @Test("uploadFormatted uses formatSpeed")
    func uploadFormatted() {
        let speed = NetworkService.NetworkSpeed(download: 0, upload: 51_200)
        #expect(speed.uploadFormatted == "50 kB/s")
    }
}
