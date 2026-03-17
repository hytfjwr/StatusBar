import Foundation
import StatusBarKit

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

    var errorDescription: String? {
        switch self {
        case .manifestNotFound(let url):
            "manifest.json not found at \(url.path)"
        case .manifestDecodingFailed(let url, let error):
            "Failed to decode manifest at \(url.path): \(error.localizedDescription)"
        case .incompatibleStatusBarKitVersion(let required, let current):
            "Incompatible StatusBarKit version: plugin requires \(required), app has \(current)"
        case .dylibNotFound(let url):
            "Plugin dylib not found at \(url.path)"
        case .dlopenFailed(let message):
            "dlopen failed: \(message)"
        case .symbolNotFound(let symbol):
            "Entry symbol '\(symbol)' not found in plugin"
        case .pluginBoxCastFailed:
            "Failed to cast plugin factory result to PluginBox"
        case .pluginFactoryFailed:
            "Plugin factory returned nil"
        }
    }
}

// MARK: - PluginLoadResult

struct PluginLoadResult: Sendable {
    let manifest: DylibPluginManifest
    let error: PluginLoadError?

    var isSuccess: Bool { error == nil }
}

// MARK: - DylibPluginLoader

@MainActor
final class DylibPluginLoader {
    static let shared = DylibPluginLoader()

    /// Retained dlopen handles keyed by plugin id. Must be released AFTER plugin objects.
    private var loadedHandles: [String: UnsafeMutableRawPointer] = [:]

    /// Retained plugin instances keyed by plugin id.
    private var loadedPlugins: [String: any StatusBarPlugin] = [:]

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

        guard fm.fileExists(atPath: dir.path) else { return }

        let store = PluginStore.shared
        do {
            try store.load()
        } catch {
            print("[DylibPluginLoader] Failed to load plugin store: \(error)")
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }

        var results: [PluginLoadResult] = []

        for bundleURL in contents where bundleURL.pathExtension == "statusplugin" {
            // Skip disabled plugins
            let bundleName = bundleURL.deletingPathExtension().lastPathComponent
            if let record = store.record(forBundleName: bundleName), !record.enabled {
                continue
            }

            do {
                let manifest = try load(bundleURL: bundleURL, into: registry)
                results.append(PluginLoadResult(manifest: manifest, error: nil))
            } catch let error as PluginLoadError {
                // Try to read manifest for error reporting
                let manifestURL = bundleURL.appendingPathComponent("manifest.json")
                let manifest = try? readManifest(at: manifestURL)
                let fallback = manifest ?? DylibPluginManifest(
                    id: bundleName,
                    name: bundleName,
                    version: "unknown",
                    statusBarKitVersion: "unknown",
                    swiftVersion: "unknown"
                )
                results.append(PluginLoadResult(manifest: fallback, error: error))
                print("[DylibPluginLoader] Failed to load \(bundleName): \(error.localizedDescription)")
            } catch {
                print("[DylibPluginLoader] Unexpected error loading \(bundleURL.lastPathComponent): \(error)")
            }
        }

        loadResults = results
    }

    // MARK: - Load Single

    /// Load a single plugin bundle and register its widgets.
    /// Returns the manifest on success.
    @discardableResult
    func load(bundleURL: URL, into registry: WidgetRegistry) throws -> DylibPluginManifest {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let manifest = try readManifest(at: manifestURL)

        // Version compatibility check
        try validateCompatibility(manifest)

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

        // Create plugin on @MainActor (we're already on MainActor)
        let plugin = box.factory()

        // Register
        registry.registerPlugin(plugin)

        // Retain handle and plugin
        loadedHandles[manifest.id] = handle
        loadedPlugins[manifest.id] = plugin

        print("[DylibPluginLoader] Loaded plugin: \(manifest.name) v\(manifest.version)")
        return manifest
    }

    // MARK: - Unload

    /// Mark a plugin for removal. Stops widgets immediately, but full cleanup requires restart.
    func markForRemoval(pluginID: String) {
        if let plugin = loadedPlugins[pluginID] {
            for widget in plugin.widgets {
                widget.stop()
            }
        }
        // Remove plugin reference first (ARC dealloc runs plugin code in the dylib)
        loadedPlugins.removeValue(forKey: pluginID)
        // Then close the dylib
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
              let hostVersion = SemanticVersion(statusBarKitVersion) else {
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

    private func findDylib(in bundleURL: URL, manifest: DylibPluginManifest) -> URL? {
        let fm = FileManager.default
        // Look for any .dylib file in the bundle
        if let contents = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) {
            return contents.first { $0.pathExtension == "dylib" }
        }
        return nil
    }
}
