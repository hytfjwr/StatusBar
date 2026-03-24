import Foundation
@testable import StatusBar
import Testing

@MainActor
struct PluginStorePersistenceTests {
    private func makeTempStore() -> (store: PluginStore, dir: URL, cleanup: @Sendable () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("registry.json")
        let cleanup: @Sendable () -> Void = { try? FileManager.default.removeItem(at: dir) }
        return (PluginStore(registryURL: url), dir, cleanup)
    }

    private func makeRecord(
        id: String = "com.test.plugin",
        name: String = "TestPlugin",
        version: String = "1.0.0",
        enabled: Bool = true,
        isLocal: Bool = false
    ) -> InstalledPluginRecord {
        InstalledPluginRecord(
            id: id, name: name, version: version,
            githubURL: "https://github.com/test/\(id)",
            bundleName: id, enabled: enabled, isLocal: isLocal
        )
    }

    // MARK: - Add

    @Test("add appends a new record")
    func addNew() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord())
        #expect(store.plugins.count == 1)
        #expect(store.plugins[0].id == "com.test.plugin")
    }

    @Test("add with existing ID replaces the record")
    func addReplace() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord(name: "V1"))
        try store.add(makeRecord(name: "V2"))
        #expect(store.plugins.count == 1)
        #expect(store.plugins[0].name == "V2")
    }

    @Test("add two records with different IDs keeps both")
    func addMultiple() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord(id: "a"))
        try store.add(makeRecord(id: "b"))
        #expect(store.plugins.count == 2)
    }

    // MARK: - Remove

    @Test("remove deletes the record by ID")
    func removeExisting() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord())
        try store.remove(id: "com.test.plugin")
        #expect(store.plugins.isEmpty)
    }

    @Test("remove with unknown ID does not throw")
    func removeUnknown() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord())
        try store.remove(id: "nonexistent")
        #expect(store.plugins.count == 1)
    }

    // MARK: - setEnabled

    @Test("setEnabled toggles the enabled flag")
    func setEnabledToggle() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord(enabled: true))
        store.setEnabled(false, for: "com.test.plugin")
        #expect(store.plugins[0].enabled == false)
    }

    @Test("setEnabled with unknown ID is a no-op")
    func setEnabledUnknown() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord(enabled: true))
        store.setEnabled(false, for: "nonexistent")
        #expect(store.plugins[0].enabled == true)
    }

    // MARK: - Load

    @Test("load with missing file yields empty plugins")
    func loadMissing() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.load()
        #expect(store.plugins.isEmpty)
    }

    @Test("load with corrupted JSON throws")
    func loadCorrupted() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("registry.json"))
        #expect(throws: (any Error).self) {
            try store.load()
        }
    }

    @Test("load with wrong schema throws")
    func loadWrongSchema() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"records\": []}".utf8).write(to: dir.appendingPathComponent("registry.json"))
        #expect(throws: (any Error).self) {
            try store.load()
        }
    }

    // MARK: - Persistence round-trip

    @Test("add then load from fresh instance preserves all fields")
    func roundTrip() throws {
        let (store1, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        let installedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = InstalledPluginRecord(
            id: "com.rt.plugin", name: "RoundTrip", version: "2.0.0",
            githubURL: "https://github.com/test/rt",
            bundleName: "roundtrip",
            installedAt: installedAt,
            enabled: false, isLocal: true
        )
        try store1.add(record)

        let store2 = PluginStore(registryURL: dir.appendingPathComponent("registry.json"))
        try store2.load()
        #expect(store2.plugins.count == 1)
        let loaded = store2.plugins[0]
        #expect(loaded.id == "com.rt.plugin")
        #expect(loaded.name == "RoundTrip")
        #expect(loaded.version == "2.0.0")
        #expect(loaded.githubURL == "https://github.com/test/rt")
        #expect(loaded.bundleName == "roundtrip")
        #expect(loaded.installedAt == installedAt)
        #expect(loaded.enabled == false)
        #expect(loaded.isLocal == true)
    }

    @Test("nil githubURL round-trips correctly")
    func roundTripNilGithubURL() throws {
        let (store1, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        let record = InstalledPluginRecord(
            id: "local", name: "Local", version: "1.0.0",
            githubURL: nil, bundleName: "local"
        )
        try store1.add(record)

        let store2 = PluginStore(registryURL: dir.appendingPathComponent("registry.json"))
        try store2.load()
        #expect(store2.plugins[0].githubURL == nil)
    }

    @Test("remove then load reflects deletion")
    func roundTripRemove() throws {
        let (store1, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try store1.add(makeRecord(id: "a"))
        try store1.add(makeRecord(id: "b"))
        try store1.remove(id: "a")

        let store2 = PluginStore(registryURL: dir.appendingPathComponent("registry.json"))
        try store2.load()
        #expect(store2.plugins.count == 1)
        #expect(store2.plugins[0].id == "b")
    }

    @Test("setEnabled persists across load")
    func roundTripSetEnabled() throws {
        let (store1, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try store1.add(makeRecord(enabled: true))
        store1.setEnabled(false, for: "com.test.plugin")

        let store2 = PluginStore(registryURL: dir.appendingPathComponent("registry.json"))
        try store2.load()
        #expect(store2.plugins[0].enabled == false)
    }

    // MARK: - Save behavior

    @Test("save creates parent directory if missing")
    func saveCreatesDirectory() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord())
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("save sets 0o600 file permissions")
    func saveFilePermissions() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try store.add(makeRecord())
        let url = dir.appendingPathComponent("registry.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
}
