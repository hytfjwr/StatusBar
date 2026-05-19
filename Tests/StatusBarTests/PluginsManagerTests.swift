import Foundation
@testable import StatusBar
import Testing

@MainActor
struct PluginsManagerTests {
    private struct TempEnv {
        let manager: PluginsManager
        let dir: URL
        let store: PluginStore
        let manifestStore: PluginsManifestStore
        let cleanup: @Sendable () -> Void
    }

    private func makeTempEnv() -> TempEnv {
        let temp = PluginTestSupport.makeTempDir()
        let manifestStore = PluginsManifestStore(
            manifestURL: temp.url.appendingPathComponent("plugins.yml"),
            lockURL: temp.url.appendingPathComponent("plugins-lock.yml")
        )
        let pluginStore = PluginStore(registryURL: temp.url.appendingPathComponent("registry.json"))
        let manager = PluginsManager(
            manifestStore: manifestStore,
            pluginStore: pluginStore,
            installer: GitHubPluginInstaller.shared
        )
        return TempEnv(
            manager: manager, dir: temp.url, store: pluginStore,
            manifestStore: manifestStore, cleanup: temp.cleanup
        )
    }

    private func makeRecord(
        id: String,
        version: String = "1.0.0",
        githubURL: String? = "https://github.com/test/plugin",
        isLocal: Bool = false
    ) -> InstalledPluginRecord {
        PluginTestSupport.makeRecord(id: id, version: version, githubURL: githubURL, isLocal: isLocal)
    }

    // MARK: - Migration

    @Test("Migration generates plugins.yml + plugins-lock.yml from registry")
    func migrationFromRegistry() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        let store = env.store
        let manifestStore = env.manifestStore
        try store.add(makeRecord(id: "com.test.a", githubURL: "https://github.com/user/repo-a"))
        try store.add(makeRecord(id: "com.test.b", githubURL: "https://github.com/user/repo-b"))

        try manager.migrateIfNeeded()

        manifestStore.load()
        #expect(manifestStore.currentManifest.plugins.count == 2)
        #expect(manifestStore.currentManifest.plugins.contains { $0.source == "github:user/repo-a" })
        #expect(manifestStore.currentManifest.plugins.contains { $0.source == "github:user/repo-b" })
        #expect(manifestStore.currentLock.plugins.count == 2)
    }

    @Test("Migration excludes local plugins")
    func migrationExcludesLocal() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        let store = env.store
        let manifestStore = env.manifestStore
        try store.add(makeRecord(
            id: "com.test.local",
            githubURL: nil,
            isLocal: true
        ))
        try store.add(makeRecord(
            id: "com.test.github",
            githubURL: "https://github.com/user/plugin"
        ))

        try manager.migrateIfNeeded()

        manifestStore.load()
        #expect(manifestStore.currentManifest.plugins.count == 1)
        #expect(manifestStore.currentManifest.plugins[0].source == "github:user/plugin")
    }

    @Test("Migration is a no-op when plugins.yml already exists")
    func migrationSkippedWhenManifestExists() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        let store = env.store
        let manifestStore = env.manifestStore
        // User-created manifest is preserved.
        let userManifest = PluginsManifest(plugins: [
            PluginsManifestEntry(source: "github:user/manual", version: "1.0.0"),
        ])
        try manifestStore.saveManifest(userManifest)

        try store.add(makeRecord(
            id: "com.test.from-registry",
            githubURL: "https://github.com/user/from-registry"
        ))

        try manager.migrateIfNeeded()

        manifestStore.load()
        #expect(manifestStore.currentManifest == userManifest)
    }

    @Test("Migration with no GitHub plugins is a no-op")
    func migrationNoGitHubPlugins() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        try env.store.add(makeRecord(id: "local", githubURL: nil, isLocal: true))

        try env.manager.migrateIfNeeded()

        // No manifest written
        let manifestPath = env.dir.appendingPathComponent("plugins.yml").path
        #expect(!FileManager.default.fileExists(atPath: manifestPath))
    }

    @Test("Migration version is normalized (no leading v)")
    func migrationNormalizesVersion() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        let store = env.store
        let manifestStore = env.manifestStore
        try store.add(makeRecord(
            id: "com.test.v",
            version: "v1.2.3",
            githubURL: "https://github.com/user/v-prefix"
        ))

        try manager.migrateIfNeeded()

        manifestStore.load()
        #expect(manifestStore.currentManifest.plugins[0].version == "1.2.3")
        #expect(manifestStore.currentLock.plugins[0].resolvedVersion == "1.2.3")
    }

    // MARK: - PluginsManifestEntry.source(fromGitHubURL:)

    @Test("source(fromGitHubURL:) parses canonical URL")
    func sourceFromCanonicalURL() {
        #expect(PluginsManifestEntry.source(fromGitHubURL: "https://github.com/user/repo") == "github:user/repo")
    }

    @Test("source(fromGitHubURL:) rejects unrelated URLs", arguments: [
        nil,
        "",
        "https://example.com/user/repo",
        "https://github.com/",
        "https://github.com/just-owner",
    ])
    func sourceFromInvalidURL(url: String?) {
        #expect(PluginsManifestEntry.source(fromGitHubURL: url) == nil)
    }

    // MARK: - manifestEntryDTOs

    @Test("manifestEntryDTOs combines manifest with lock")
    func manifestDTOs() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        let manifestStore = env.manifestStore
        try manifestStore.saveManifest(PluginsManifest(plugins: [
            PluginsManifestEntry(source: "github:user/a", version: "latest"),
            PluginsManifestEntry(source: "github:user/b", version: "1.0.0"),
        ]))
        try manifestStore.saveLock(PluginsLock(plugins: [
            PluginsLockEntry(
                source: "github:user/a", resolvedVersion: "2.5.0",
                pluginID: "com.user.a", bundleName: "A",
                assetURL: "https://objects.githubusercontent.com/x",
                zipSHA256: "abc",
                resolvedAt: Date()
            ),
            // user/b is intentionally absent from the lock (unresolved).
        ]))

        let dtos = manager.manifestEntryDTOs()

        #expect(dtos.count == 2)
        let a = try #require(dtos.first { $0.source == "github:user/a" })
        #expect(a.declaredVersion == "latest")
        #expect(a.resolvedVersion == "2.5.0")
        #expect(a.zipSHA256 == "abc")
        #expect(a.pluginID == "com.user.a")

        let b = try #require(dtos.first { $0.source == "github:user/b" })
        #expect(b.declaredVersion == "1.0.0")
        #expect(b.resolvedVersion == nil)
        #expect(b.zipSHA256 == nil)
        #expect(b.pluginID == nil)
    }

    // MARK: - remove guards

    @Test("remove throws for unknown plugin ID")
    func removeUnknown() {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        #expect(throws: PluginsManagerError.self) {
            try manager.remove(pluginID: "does-not-exist")
        }
    }

    @Test("remove rejects local plugins")
    func removeLocalRejected() throws {
        let env = makeTempEnv()
        defer { env.cleanup() }
        let manager = env.manager
        let store = env.store
        try store.add(makeRecord(id: "com.local", githubURL: nil, isLocal: true))
        #expect(throws: PluginsManagerError.self) {
            try manager.remove(pluginID: "com.local")
        }
    }
}
