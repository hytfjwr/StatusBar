import Foundation
@testable import StatusBar
import Testing

struct InstalledPluginRecordUpdatingTests {
    let base = InstalledPluginRecord(
        id: "com.test.plugin",
        name: "TestPlugin",
        version: "1.0.0",
        githubURL: "https://github.com/test/plugin",
        bundleName: "test",
        installedAt: Date(timeIntervalSince1970: 1_000_000),
        enabled: true,
        isLocal: false
    )

    @Test("No arguments returns identical record")
    func noArgs() {
        let updated = base.updating()
        #expect(updated.id == base.id)
        #expect(updated.name == base.name)
        #expect(updated.version == base.version)
        #expect(updated.githubURL == base.githubURL)
        #expect(updated.bundleName == base.bundleName)
        #expect(updated.installedAt == base.installedAt)
        #expect(updated.enabled == base.enabled)
        #expect(updated.isLocal == base.isLocal)
    }

    @Test("Overrides only the specified fields")
    func partialOverride() {
        let updated = base.updating(name: "Renamed", version: "2.0.0")
        #expect(updated.name == "Renamed")
        #expect(updated.version == "2.0.0")
        // Unchanged
        #expect(updated.githubURL == base.githubURL)
        #expect(updated.installedAt == base.installedAt)
        #expect(updated.enabled == base.enabled)
    }

    @Test("id, bundleName, isLocal are always preserved")
    func immutableFields() {
        let updated = base.updating(
            name: "X", version: "X", githubURL: "X", installedAt: Date(), enabled: false
        )
        #expect(updated.id == base.id)
        #expect(updated.bundleName == base.bundleName)
        #expect(updated.isLocal == base.isLocal)
    }

    @Test("githubURL nil preserves existing, .some(nil) clears it")
    func doubleOptionalGithubURL() {
        // nil (default) → preserves
        let preserved = base.updating()
        #expect(preserved.githubURL == "https://github.com/test/plugin")

        // .some(nil) → explicitly clears
        let cleared = base.updating(githubURL: .some(nil))
        #expect(cleared.githubURL == nil)

        // .some("new") → overrides
        let overridden = base.updating(githubURL: "https://github.com/new/repo")
        #expect(overridden.githubURL == "https://github.com/new/repo")
    }
}
