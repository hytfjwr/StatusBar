import Foundation
@testable import StatusBar
import Testing
import Yams

@MainActor
struct PluginsManifestStoreTests {
    private func makeTempStore() -> (store: PluginsManifestStore, dir: URL, cleanup: @Sendable () -> Void) {
        let temp = PluginTestSupport.makeTempDir()
        let store = PluginsManifestStore(
            manifestURL: temp.url.appendingPathComponent("plugins.yml"),
            lockURL: temp.url.appendingPathComponent("plugins-lock.yml")
        )
        return (store, temp.url, temp.cleanup)
    }

    // MARK: - Round-trip

    @Test("PluginsManifest round-trips through YAML")
    func manifestRoundTrip() throws {
        let original = PluginsManifest(plugins: [
            PluginsManifestEntry(source: "github:user/weather-plugin", version: "1.2.0"),
            PluginsManifestEntry(source: "github:user/spotify", version: "latest"),
        ])
        let yaml = try YAMLEncoder().encode(original)
        let decoded = try YAMLDecoder().decode(PluginsManifest.self, from: yaml)
        #expect(decoded == original)
    }

    @Test("source(fromGitHubURL:) is the inverse of parseGitHubSource()")
    func sourceRoundTrip() throws {
        let original = "https://github.com/owner/repo"
        let source = PluginsManifestEntry.source(fromGitHubURL: original)
        #expect(source == "github:owner/repo")
        let parsed = try PluginsManifestEntry(source: #require(source), version: "1.0.0").parseGitHubSource()
        #expect(parsed?.owner == "owner")
        #expect(parsed?.repo == "repo")
    }

    @Test("PluginsLock round-trips through YAML")
    func lockRoundTrip() throws {
        let resolvedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = PluginsLock(plugins: [
            PluginsLockEntry(
                source: "github:user/weather-plugin",
                resolvedVersion: "1.2.0",
                pluginID: "com.user.weather",
                bundleName: "Weather",
                assetURL: "https://objects.githubusercontent.com/abc",
                zipSHA256: "deadbeef",
                resolvedAt: resolvedAt
            ),
        ])
        let yaml = try YAMLEncoder().encode(original)
        let decoded = try YAMLDecoder().decode(PluginsLock.self, from: yaml)
        #expect(decoded == original)
    }

    @Test("Lock entry round-trips even when assetURL/zipSHA256 are nil (post-migration state)")
    func lockRoundTripUnresolved() throws {
        let entry = PluginsLockEntry(
            source: "github:user/x",
            resolvedVersion: "0.1.0",
            pluginID: "com.x",
            bundleName: "X",
            assetURL: nil,
            zipSHA256: nil,
            resolvedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let lock = PluginsLock(plugins: [entry])
        let yaml = try YAMLEncoder().encode(lock)
        let decoded = try YAMLDecoder().decode(PluginsLock.self, from: yaml)
        #expect(decoded.plugins[0].assetURL == nil)
        #expect(decoded.plugins[0].zipSHA256 == nil)
    }

    // MARK: - parseGitHubSource

    @Test("parseGitHubSource accepts well-formed entries")
    func parseGitHubSourceValid() {
        let entry = PluginsManifestEntry(source: "github:owner/repo", version: "1.0.0")
        let parsed = entry.parseGitHubSource()
        #expect(parsed?.owner == "owner")
        #expect(parsed?.repo == "repo")
    }

    @Test("parseGitHubSource rejects malformed entries", arguments: [
        "owner/repo", // missing prefix
        "github:", // empty path
        "github:owner", // missing repo
        "github:/repo", // missing owner
        "github:owner/", // missing repo
    ])
    func parseGitHubSourceInvalid(source: String) {
        let entry = PluginsManifestEntry(source: source, version: "1.0.0")
        #expect(entry.parseGitHubSource() == nil)
    }

    // MARK: - Save / Load

    @Test("Save then load yields the same manifest")
    func saveLoadManifest() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let manifest = PluginsManifest(plugins: [
            PluginsManifestEntry(source: "github:a/b", version: "1.0.0"),
        ])
        try store.saveManifest(manifest)
        store.load()
        #expect(store.currentManifest == manifest)
    }

    @Test("Save then load yields the same lock")
    func saveLoadLock() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let lock = PluginsLock(plugins: [
            PluginsLockEntry(
                source: "github:a/b",
                resolvedVersion: "1.0.0",
                pluginID: "com.a.b",
                bundleName: "B",
                assetURL: "https://objects.githubusercontent.com/x",
                zipSHA256: "deadbeef",
                resolvedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ])
        try store.saveLock(lock)
        store.load()
        #expect(store.currentLock == lock)
    }

    @Test("Load with no files yields empty defaults")
    func loadMissing() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        store.load()
        #expect(store.currentManifest == .empty)
        #expect(store.currentLock == .empty)
        #expect(!store.manifestExists)
    }

    @Test("Empty manifest YAML loads as empty")
    func loadEmptyManifest() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try Data("".utf8).write(to: dir.appendingPathComponent("plugins.yml"))
        store.load()
        #expect(store.currentManifest == .empty)
    }

    @Test("reload() throws on parse error so callers can preserve previous state")
    func reloadThrowsOnParseError() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try Data("plugins: [not-a-list".utf8).write(to: dir.appendingPathComponent("plugins.yml"))
        #expect(throws: (any Error).self) {
            try store.reload()
        }
    }

    @Test("Save creates parent directory if missing")
    func saveCreatesDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        // No mkdir; PluginsManifestStore should create it.
        let store = PluginsManifestStore(
            manifestURL: dir.appendingPathComponent("plugins.yml"),
            lockURL: dir.appendingPathComponent("plugins-lock.yml")
        )
        try store.saveManifest(PluginsManifest(plugins: []))
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }
}
