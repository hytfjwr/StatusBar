import Foundation
@testable import StatusBar
import Testing

struct NetworkSpeedTests {

    // MARK: - formatSpeed

    @Test("Formats zero bytes as 0 kB/s")
    func zeroBytes() {
        #expect(NetworkService.NetworkSnapshot.formatSpeed(0) == "0 kB/s")
    }

    @Test("Formats sub-kilobyte speeds as kB/s")
    func subKilobyte() {
        // 512 bytes = 0.5 KB
        #expect(NetworkService.NetworkSnapshot.formatSpeed(512) == "0 kB/s")
    }

    @Test("Formats kilobyte range as kB/s")
    func kilobyteRange() {
        // 100 KB = 102400 bytes
        let result = NetworkService.NetworkSnapshot.formatSpeed(102_400)
        #expect(result == "100 kB/s")
    }

    @Test("Formats near-megabyte as kB/s")
    func nearMegabyte() {
        // 999 KB = 1023 * 1024 bytes → still kB/s
        let result = NetworkService.NetworkSnapshot.formatSpeed(999 * 1_024)
        #expect(result == "999 kB/s")
    }

    @Test("Switches to MB/s above 999 kB/s")
    func megabyteRange() {
        // 1000 KB = 1000 * 1024 bytes → 1000 kB/s > 999 → MB/s
        let result = NetworkService.NetworkSnapshot.formatSpeed(1_000 * 1_024)
        #expect(result.hasSuffix("MB/s"))
    }

    @Test("Formats multi-megabyte speeds")
    func multiMegabyte() {
        // 10 MB = 10 * 1024 * 1024 bytes
        let result = NetworkService.NetworkSnapshot.formatSpeed(10 * 1_024 * 1_024)
        #expect(result == "10.0 MB/s")
    }

    // MARK: - NetworkSnapshot properties

    @Test("downloadFormatted uses formatSpeed")
    func downloadFormatted() {
        let snapshot = NetworkService.NetworkSnapshot(download: 102_400, upload: 0, interfaces: [])
        #expect(snapshot.downloadFormatted == "100 kB/s")
    }

    @Test("uploadFormatted uses formatSpeed")
    func uploadFormatted() {
        let snapshot = NetworkService.NetworkSnapshot(download: 0, upload: 51_200, interfaces: [])
        #expect(snapshot.uploadFormatted == "50 kB/s")
    }

    // MARK: - computeInterfaceSpeeds

    @Test("Computes bytes/sec from the delta between two snapshots")
    func normalDelta() {
        let previous = ["en0": (rx: UInt64(1_000), tx: UInt64(500))]
        let current = ["en0": (rx: UInt64(2_024), tx: UInt64(1_524))]

        let result = NetworkService.computeInterfaceSpeeds(previous: previous, current: current, elapsed: 2.0)

        #expect(result.count == 1)
        #expect(result[0].name == "en0")
        #expect(result[0].download == 512)
        #expect(result[0].upload == 512)
    }

    @Test("Reports 0 for a direction whose counter went backwards (reset)")
    func counterResetReportsZero() {
        let previous = ["en0": (rx: UInt64(5_000), tx: UInt64(5_000))]
        let current = ["en0": (rx: UInt64(1_000), tx: UInt64(6_000))]

        let result = NetworkService.computeInterfaceSpeeds(previous: previous, current: current, elapsed: 1.0)

        #expect(result[0].download == 0)
        #expect(result[0].upload == 1_000)
    }

    @Test("Includes interfaces absent from the previous snapshot with 0/0 speeds")
    func newInterfaceIncludedWithZeroSpeeds() {
        let previous: [String: (rx: UInt64, tx: UInt64)] = [:]
        let current = ["utun0": (rx: UInt64(1_000), tx: UInt64(1_000))]

        let result = NetworkService.computeInterfaceSpeeds(previous: previous, current: current, elapsed: 1.0)

        #expect(result.count == 1)
        #expect(result[0].name == "utun0")
        #expect(result[0].download == 0)
        #expect(result[0].upload == 0)
    }

    @Test("Returns an empty array when elapsed is zero")
    func zeroElapsedReturnsEmpty() {
        let previous = ["en0": (rx: UInt64(0), tx: UInt64(0))]
        let current = ["en0": (rx: UInt64(1_000), tx: UInt64(1_000))]

        let result = NetworkService.computeInterfaceSpeeds(previous: previous, current: current, elapsed: 0)

        #expect(result.isEmpty)
    }

    @Test("Sorts results by interface name ascending")
    func sortedByName() {
        let previous: [String: (rx: UInt64, tx: UInt64)] = [:]
        let current = [
            "utun0": (rx: UInt64(0), tx: UInt64(0)),
            "en0": (rx: UInt64(0), tx: UInt64(0)),
            "en1": (rx: UInt64(0), tx: UInt64(0)),
        ]

        let result = NetworkService.computeInterfaceSpeeds(previous: previous, current: current, elapsed: 1.0)

        #expect(result.map(\.name) == ["en0", "en1", "utun0"])
    }
}
