import Foundation
@testable import StatusBar

/// Shared test helpers for plugin-related test suites. Centralizing these avoids drift between
/// `PluginStorePersistenceTests`, `PluginsManifestStoreTests`, and `PluginsManagerTests`.
@MainActor
enum PluginTestSupport {
    struct TempDir {
        let url: URL
        let cleanup: @Sendable () -> Void
    }

    /// Create a fresh temporary directory plus a teardown closure.
    static func makeTempDir() -> TempDir {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDir(url: url) { try? FileManager.default.removeItem(at: url) }
    }

    /// Build an `InstalledPluginRecord` with sensible defaults for tests.
    static func makeRecord(
        id: String = "com.test.plugin",
        name: String? = nil,
        version: String = "1.0.0",
        githubURL: String? = nil,
        bundleName: String? = nil,
        installedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        enabled: Bool = true,
        isLocal: Bool = false
    ) -> InstalledPluginRecord {
        InstalledPluginRecord(
            id: id,
            name: name ?? id,
            version: version,
            githubURL: githubURL ?? "https://github.com/test/\(id)",
            bundleName: bundleName ?? id,
            installedAt: installedAt,
            enabled: enabled,
            isLocal: isLocal
        )
    }
}
