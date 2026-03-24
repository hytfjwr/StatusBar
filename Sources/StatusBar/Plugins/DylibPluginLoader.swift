import CryptoKit
import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "DylibPluginLoader")

// MARK: - PluginLoadError

enum PluginLoadError: Error, LocalizedError {
    case manifestNotFound(URL)
    case manifestDecodingFailed(URL, any Error)
    case incompatibleStatusBarKitVersion(required: String, current: String)
    case dylibNotFound(URL)
    case dlopenFailed(String)
    case symbolNotFound(String)
    case pluginBoxCastFailed
    case pluginFactoryFailed
    case sha256Mismatch(expected: String, actual: String)
    case invalidManifestField(String, String)
    case duplicatePluginID(String)

    var errorDescription: String? {
        func redact(_ url: URL) -> String {
            url.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
        }
        switch self {
        case let .manifestNotFound(url):
            return "manifest.json not found at \(redact(url))"
        case let .manifestDecodingFailed(url, error):
            return "Failed to decode manifest at \(redact(url)): \(error.localizedDescription)"
        case let .incompatibleStatusBarKitVersion(required, current):
            return "Incompatible StatusBarKit version: plugin requires \(required), app has \(current)"
        case let .dylibNotFound(url):
            return "Plugin dylib not found at \(redact(url))"
        case let .dlopenFailed(message):
            return "dlopen failed: \(message)"
        case let .symbolNotFound(symbol):
            return "Entry symbol '\(symbol)' not found in plugin"
        case .pluginBoxCastFailed:
            return "Failed to cast plugin factory result to PluginBox"
        case .pluginFactoryFailed:
            return "Plugin factory returned nil"
        case let .sha256Mismatch(expected, actual):
            return "SHA-256 mismatch: expected \(expected), got \(actual)"
        case let .invalidManifestField(field, _):
            return "Invalid manifest field '\(field)': contains disallowed characters"
        case let .duplicatePluginID(id):
            return "Duplicate plugin ID: '\(id)' is already loaded"
        }
    }
}

// MARK: - PluginLoadResult

struct PluginLoadResult {
    let manifest: DylibPluginManifest
    let error: PluginLoadError?

    var isSuccess: Bool {
        error == nil
    }
}

// MARK: - DylibPluginLoader

@MainActor
final class DylibPluginLoader {
    static let shared = DylibPluginLoader()

    /// Retained dlopen handles keyed by plugin id. Must be released AFTER plugin objects.
    private var loadedHandles: [String: UnsafeMutableRawPointer] = [:]

    /// Retained plugin instances keyed by plugin id.
    private var loadedPlugins: [String: any StatusBarPlugin] = [:]

    /// Dev-loaded plugin IDs, tracked separately from installed plugins.
    private var devPluginIDs: Set<String> = []

    /// Results from the most recent loadAll call.
    private(set) var loadResults: [PluginLoadResult] = []

    private init() {}

    /// The plugins directory: ~/.config/statusbar/plugins/
    private var pluginsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar/plugins")
    }

    // MARK: - Load All

    /// Scan the plugins directory and load all valid .statusplugin bundles.
    func loadAll(into registry: WidgetRegistry) {
        let fm = FileManager.default
        let dir = pluginsDirectory

        guard fm.fileExists(atPath: dir.path) else {
            return
        }

        let store = PluginStore.shared
        do {
            try store.load()
        } catch {
            // If store is corrupted, skip all plugin loading to prevent
            // re-enabling user-disabled plugins
            logger.error("Plugin store corrupted — skipping all plugin loading: \(error.localizedDescription)")
            return
        }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
        } catch {
            logger.error("Failed to read plugins directory: \(error.localizedDescription)")
            return
        }

        var results: [PluginLoadResult] = []

        for bundleURL in contents where bundleURL.pathExtension == "statusplugin" {
            let bundleName = bundleURL.deletingPathExtension().lastPathComponent
            if let record = store.record(forBundleName: bundleName), !record.enabled {
                continue
            }
            if let result = loadBundle(at: bundleURL, into: registry, store: store) {
                results.append(result)
            }
        }

        loadResults = results
    }

    /// Load a single bundle during `loadAll`, syncing or registering the plugin store record.
    /// Returns `nil` for unexpected (non-plugin) errors, which are only logged.
    private func loadBundle(
        at bundleURL: URL,
        into registry: WidgetRegistry,
        store: PluginStore
    ) -> PluginLoadResult? {
        let bundleName = bundleURL.deletingPathExtension().lastPathComponent
        do {
            let manifest = try load(bundleURL: bundleURL, into: registry)
            syncStoreRecord(for: bundleName, manifest: manifest, store: store)
            return PluginLoadResult(manifest: manifest, error: nil)
        } catch let error as PluginLoadError {
            let manifestURL = bundleURL.appendingPathComponent("manifest.json")
            let manifest = try? readManifest(at: manifestURL)
            let fallback = manifest ?? DylibPluginManifest(
                id: bundleName,
                name: bundleName,
                version: "unknown",
                statusBarKitVersion: "unknown",
                swiftVersion: "unknown"
            )
            logger.error("Failed to load \(bundleName): \(error.localizedDescription)")
            return PluginLoadResult(manifest: fallback, error: error)
        } catch {
            logger.error("Unexpected error loading \(bundleURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Sync or auto-register a plugin store record after successful loading.
    private func syncStoreRecord(for bundleName: String, manifest: DylibPluginManifest, store: PluginStore) {
        if let existing = store.record(forBundleName: bundleName) {
            // Sync name from disk manifest; sync version only for local plugins
            // (GitHub-installed plugins use tag-based versions which may differ from manifest)
            let newName = existing.name != manifest.name ? manifest.name : nil
            let newVersion = existing.isLocal && existing.version != manifest.version
                ? manifest.version : nil
            if newName != nil || newVersion != nil {
                let synced = existing.updating(name: newName, version: newVersion)
                do {
                    try store.add(synced)
                    logger.info("Synced registry for \(bundleName): name=\(synced.name), version=\(synced.version)")
                } catch {
                    logger.warning("Failed to sync registry for \(bundleName): \(error.localizedDescription)")
                }
            }
        } else {
            // Auto-register in PluginStore if not already tracked (e.g. make dev)
            let record = InstalledPluginRecord(
                id: manifest.id,
                name: manifest.name,
                version: manifest.version,
                githubURL: manifest.homepage,
                bundleName: bundleName,
                isLocal: true
            )
            do {
                try store.add(record)
            } catch {
                logger.warning("Failed to auto-register plugin \(bundleName): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Load Single

    /// Load a single plugin bundle and register its widgets.
    /// Returns the manifest on success.
    @discardableResult
    func load(bundleURL: URL, into registry: WidgetRegistry) throws -> DylibPluginManifest {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let manifest = try readManifest(at: manifestURL)

        // Validate manifest fields
        try validateManifestFields(manifest)

        // Version compatibility check
        try validateCompatibility(manifest)

        // Reject duplicate plugin IDs
        guard loadedHandles[manifest.id] == nil else {
            throw PluginLoadError.duplicatePluginID(manifest.id)
        }

        // Find the dylib
        let dylibURL = findDylib(in: bundleURL, manifest: manifest)
        guard let dylibURL, FileManager.default.fileExists(atPath: dylibURL.path) else {
            throw PluginLoadError.dylibNotFound(bundleURL)
        }

        // SHA-256 integrity verification
        try verifyDylibIntegrity(at: dylibURL, manifest: manifest)

        // dlopen
        guard let handle = dlopen(dylibURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let errorMessage = String(cString: dlerror())
            throw PluginLoadError.dlopenFailed(errorMessage)
        }

        // dlsym for the factory function
        let symbolName = manifest.entrySymbol
        guard let sym = dlsym(handle, symbolName) else {
            dlclose(handle)
            throw PluginLoadError.symbolNotFound(symbolName)
        }

        // Cast to C function pointer and call
        typealias PluginFactory = @convention(c) () -> UnsafeMutableRawPointer
        let factory = unsafeBitCast(sym, to: PluginFactory.self)
        let rawPtr = factory()

        // Extract PluginBox
        let anyObject = Unmanaged<AnyObject>.fromOpaque(rawPtr).takeRetainedValue()
        guard let box = anyObject as? PluginBox else {
            dlclose(handle)
            throw PluginLoadError.pluginBoxCastFailed
        }

        // Create plugin on @MainActor (we're already on MainActor)
        let plugin = box.factory()

        // Register
        registry.registerPlugin(plugin)

        // Retain handle and plugin
        loadedHandles[manifest.id] = handle
        loadedPlugins[manifest.id] = plugin

        logger.info("Loaded plugin: \(manifest.name) v\(manifest.version)")
        return manifest
    }

    // MARK: - Dev Load

    /// Load a plugin in development mode (skips version compatibility checks).
    @discardableResult
    func loadDev(bundleURL: URL, into registry: WidgetRegistry) throws -> DylibPluginManifest {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let manifest = try readManifest(at: manifestURL)

        // Validate manifest fields (security: sanitize entrySymbol etc.)
        try validateManifestFields(manifest)

        // Skip version compatibility check for dev mode

        // Find the dylib
        let dylibURL = findDylib(in: bundleURL, manifest: manifest)
        guard let dylibURL, FileManager.default.fileExists(atPath: dylibURL.path) else {
            throw PluginLoadError.dylibNotFound(bundleURL)
        }

        // dlopen
        guard let handle = dlopen(dylibURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let errorMessage = String(cString: dlerror())
            throw PluginLoadError.dlopenFailed(errorMessage)
        }

        // dlsym for the factory function
        let symbolName = manifest.entrySymbol
        guard let sym = dlsym(handle, symbolName) else {
            dlclose(handle)
            throw PluginLoadError.symbolNotFound(symbolName)
        }

        // Cast to C function pointer and call
        typealias PluginFactory = @convention(c) () -> UnsafeMutableRawPointer
        let factory = unsafeBitCast(sym, to: PluginFactory.self)
        let rawPtr = factory()

        // Extract PluginBox
        let anyObject = Unmanaged<AnyObject>.fromOpaque(rawPtr).takeRetainedValue()
        guard let box = anyObject as? PluginBox else {
            dlclose(handle)
            throw PluginLoadError.pluginBoxCastFailed
        }

        let plugin = box.factory()
        registry.registerPlugin(plugin)

        loadedHandles[manifest.id] = handle
        loadedPlugins[manifest.id] = plugin
        devPluginIDs.insert(manifest.id)

        logger.info("Dev-loaded plugin: \(manifest.name) v\(manifest.version)")
        return manifest
    }

    // MARK: - Query

    /// Whether a plugin is currently loaded in memory.
    func isLoaded(_ pluginID: String) -> Bool {
        loadedPlugins[pluginID] != nil
    }

    /// Whether a plugin was loaded in dev mode.
    func isDevLoaded(_ pluginID: String) -> Bool {
        devPluginIDs.contains(pluginID)
    }

    /// Widget IDs belonging to a loaded plugin.
    func widgetIDs(for pluginID: String) -> [String] {
        loadedPlugins[pluginID]?.widgets.map(\.id) ?? []
    }

    // MARK: - Unload

    /// Mark a plugin for removal. Stops widgets immediately, but full cleanup requires restart.
    func markForRemoval(pluginID: String) {
        if let plugin = loadedPlugins[pluginID] {
            for widget in plugin.widgets {
                widget.stop()
            }
        }
        teardown(pluginID: pluginID)
    }

    // MARK: - Hot Reload

    /// Unload an existing plugin and load the updated version from disk.
    @discardableResult
    func reload(pluginID: String, bundleURL: URL, into registry: WidgetRegistry) throws -> DylibPluginManifest {
        // Remove widgets from registry (releases AnyStatusBarWidget closure captures)
        let oldWidgetIDs = Set(widgetIDs(for: pluginID))
        registry.unregisterWidgets(ids: oldWidgetIDs)

        // Tear down old plugin and dylib, then load the new version
        teardown(pluginID: pluginID)
        let manifest = try load(bundleURL: bundleURL, into: registry)
        logger.info("Hot-reloaded plugin: \(manifest.name) v\(manifest.version)")
        return manifest
    }

    /// Release plugin instance and close dylib handle.
    private func teardown(pluginID: String) {
        loadedPlugins.removeValue(forKey: pluginID)
        if let handle = loadedHandles.removeValue(forKey: pluginID) {
            dlclose(handle)
        }
    }

    // MARK: - Private Helpers

    private func readManifest(at url: URL) throws -> DylibPluginManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PluginLoadError.manifestNotFound(url)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DylibPluginManifest.self, from: data)
        } catch {
            throw PluginLoadError.manifestDecodingFailed(url, error)
        }
    }

    private func validateCompatibility(_ manifest: DylibPluginManifest) throws {
        guard let pluginVersion = SemanticVersion(manifest.statusBarKitVersion),
              let hostVersion = SemanticVersion(statusBarKitVersion)
        else {
            throw PluginLoadError.incompatibleStatusBarKitVersion(
                required: manifest.statusBarKitVersion,
                current: statusBarKitVersion
            )
        }
        guard hostVersion.isCompatible(with: pluginVersion) else {
            throw PluginLoadError.incompatibleStatusBarKitVersion(
                required: manifest.statusBarKitVersion,
                current: statusBarKitVersion
            )
        }
    }

    /// Validate manifest fields contain only safe characters.
    func validateManifestFields(_ manifest: DylibPluginManifest) throws {
        let idPattern = /^[a-zA-Z0-9._-]+$/
        let symbolPattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/
        let versionPattern = /^[a-zA-Z0-9._-]+$/
        let namePattern = /^[a-zA-Z0-9._\- ]+$/

        if manifest.id.wholeMatch(of: idPattern) == nil {
            throw PluginLoadError.invalidManifestField("id", manifest.id)
        }
        if manifest.entrySymbol.wholeMatch(of: symbolPattern) == nil {
            throw PluginLoadError.invalidManifestField("entrySymbol", manifest.entrySymbol)
        }
        if manifest.version.wholeMatch(of: versionPattern) == nil {
            throw PluginLoadError.invalidManifestField("version", manifest.version)
        }
        if manifest.name.wholeMatch(of: namePattern) == nil {
            throw PluginLoadError.invalidManifestField("name", manifest.name)
        }
    }

    private func findDylib(in bundleURL: URL, manifest: DylibPluginManifest) -> URL? {
        let fm = FileManager.default
        // Look for any .dylib file in the bundle
        if let contents = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) {
            return contents.first { $0.pathExtension == "dylib" }
        }
        return nil
    }

    /// Verify dylib SHA-256 hash against manifest if the manifest specifies one.
    private func verifyDylibIntegrity(at dylibURL: URL, manifest: DylibPluginManifest) throws {
        guard let expectedHash = manifest.sha256 else {
            logger.warning("Plugin \(manifest.name) has no sha256 in manifest — skipping integrity check")
            return
        }

        let dylibData = try Data(contentsOf: dylibURL)
        let actualHash = SHA256.hash(data: dylibData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actualHash == expectedHash.lowercased() else {
            logger.error("SHA-256 mismatch for \(manifest.name): expected \(expectedHash), got \(actualHash)")
            throw PluginLoadError.sha256Mismatch(expected: expectedHash, actual: actualHash)
        }

        logger.debug("SHA-256 verified for \(manifest.name)")
    }
}
