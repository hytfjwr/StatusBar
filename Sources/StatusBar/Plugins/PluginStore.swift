import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "PluginStore")

// MARK: - InstalledPluginRecord

struct InstalledPluginRecord: Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let githubURL: String?
    let bundleName: String
    let installedAt: Date
    var enabled: Bool
    /// True when the plugin was discovered on disk without a GitHub install (e.g. `make dev`).
    let isLocal: Bool

    init(
        id: String,
        name: String,
        version: String,
        githubURL: String?,
        bundleName: String,
        installedAt: Date = Date(),
        enabled: Bool = true,
        isLocal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.githubURL = githubURL
        self.bundleName = bundleName
        self.installedAt = installedAt
        self.enabled = enabled
        self.isLocal = isLocal
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        githubURL = try container.decodeIfPresent(String.self, forKey: .githubURL)
        bundleName = try container.decode(String.self, forKey: .bundleName)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
    }
}

// MARK: - PluginStoreData

private struct PluginStoreData: Codable {
    var plugins: [InstalledPluginRecord]
}

// MARK: - PluginStore

@MainActor
@Observable
final class PluginStore {
    static let shared = PluginStore()

    private(set) var plugins: [InstalledPluginRecord] = []

    private var registryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar/plugins/registry.json")
    }

    private init() {}

    // MARK: - CRUD

    func add(_ record: InstalledPluginRecord) throws {
        plugins.removeAll { $0.id == record.id }
        plugins.append(record)
        try save()
    }

    func remove(id: String) throws {
        plugins.removeAll { $0.id == id }
        try save()
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].enabled = enabled
        do {
            try save()
        } catch {
            logger.error("Failed to save plugin store after setEnabled(\(enabled)) for \(id): \(error.localizedDescription)")
        }
    }

    func record(forBundleName name: String) -> InstalledPluginRecord? {
        plugins.first { $0.bundleName == name }
    }

    func record(forID id: String) -> InstalledPluginRecord? {
        plugins.first { $0.id == id }
    }

    // MARK: - Persistence

    func load() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: registryURL.path) else {
            plugins = []
            return
        }
        let data = try Data(contentsOf: registryURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(PluginStoreData.self, from: data)
        plugins = store.plugins
    }

    func save() throws {
        let fm = FileManager.default
        let dir = registryURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PluginStoreData(plugins: plugins))
        try data.write(to: registryURL, options: .atomic)
    }
}
