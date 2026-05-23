import Foundation
@testable import StatusBar
import Testing

@MainActor
struct AppUpdateServiceTests {

    // MARK: - ReleaseInfo formatting

    @Test("ReleaseInfo formats size and date when both present")
    func releaseInfoFormatsValues() {
        let date = Date(timeIntervalSince1970: 1_716_336_000) // 2024-05-22 UTC
        let info = AppUpdateService.ReleaseInfo(
            version: "0.18.0",
            sizeBytes: 12_300_000,
            publishedAt: date
        )

        #expect(info.formattedSize != nil)
        #expect(info.formattedSize?.contains("MB") == true)
        #expect(info.formattedDate != nil)
    }

    @Test("ReleaseInfo returns nil for missing fields")
    func releaseInfoNilFields() {
        let info = AppUpdateService.ReleaseInfo(
            version: "0.18.0",
            sizeBytes: nil,
            publishedAt: nil
        )
        #expect(info.formattedSize == nil)
        #expect(info.formattedDate == nil)
    }

    // MARK: - Skip logic

    @Test("Skip and clearSkipped round-trip through the service")
    func skipRoundTrip() {
        let service = AppUpdateService.shared
        service.clearSkipped()
        service.skip(version: "0.18.0")
        #expect(service.skippedVersion == "0.18.0")

        service.clearSkipped()
        #expect(service.skippedVersion == nil)
    }

    @Test("Skip persists across reads of UserDefaults")
    func skipPersists() {
        let service = AppUpdateService.shared
        service.clearSkipped()
        service.skip(version: "0.19.0")
        let stored = UserDefaults.standard.string(forKey: "appUpdate.skippedVersion")
        #expect(stored == "0.19.0")
        service.clearSkipped()
        #expect(UserDefaults.standard.string(forKey: "appUpdate.skippedVersion") == nil)
    }
}
