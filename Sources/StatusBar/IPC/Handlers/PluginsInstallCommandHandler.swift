import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "PluginsInstallCommandHandler")

// MARK: - PluginsInstallCommandHandler

@MainActor
struct PluginsInstallCommandHandler: CommandHandling {
    let commandKey = "pluginsInstall"

    func handle(_ command: IPCCommand) async throws -> IPCPayload {
        guard case let .pluginsInstall(source, version) = command else {
            throw IPCError.unknownCommand
        }
        // When the CLI omits --version, preserve any pre-existing pin in plugins.yml.
        // Otherwise `add()` would overwrite `version: 1.2.0` with `version: latest`,
        // silently undoing the user's pin on a routine reinstall.
        let manager = PluginsManager.shared
        let resolvedVersion: String = if let version {
            version
        } else if let existing = manager.manifestStore.currentManifest.plugins.first(
            where: { $0.source.lowercased() == source.lowercased() }
        ) {
            existing.version
        } else {
            "latest"
        }

        let result: PluginsManager.AddResult
        do {
            result = try await manager.add(source: source, version: resolvedVersion)
        } catch {
            throw IPCError.internalError(error.localizedDescription)
        }
        let record = result.record

        // Only hot-load when something on disk actually changed. Calling `reload()` on an
        // already-loaded plugin at the same version tears down its widgets and rebuilds them
        // from disk, throwing away graph buffers, popup state, and other in-memory state —
        // surprising behavior for an idempotent `sbar plugins install` re-run.
        if result.action != .skipped {
            _ = hotLoad(record: record)
        }

        return .pluginInstalled(InstalledPluginDTO(
            id: record.id,
            name: record.name,
            version: record.version,
            bundleName: record.bundleName,
            source: source,
            installedAt: record.installedAt
        ))
    }

    /// Hot-load (or hot-reload, when the plugin was already loaded at a previous version) and
    /// start any newly added widgets. Returns true when the widgets are usable without restart.
    private func hotLoad(record: InstalledPluginRecord) -> Bool {
        let loader = DylibPluginLoader.shared
        let registry = WidgetRegistry.shared
        let bundleURL = Self.bundleURL(for: record)

        if loader.isLoaded(record.id) {
            do {
                _ = try loader.reload(pluginID: record.id, bundleURL: bundleURL, into: registry)
                registry.finalizeRegistration()
                startWidgets(for: record.id, in: registry, loader: loader)
                return true
            } catch {
                logger.warning("Hot-reload failed for \(record.id): \(error.localizedDescription)")
                return false
            }
        }

        let existingIDs = Set(registry.layout.map(\.id))
        do {
            _ = try loader.load(bundleURL: bundleURL, into: registry)
            registry.finalizeRegistration()
            let widgets = registry.leftWidgets + registry.centerWidgets + registry.rightWidgets
            for widget in widgets where !existingIDs.contains(widget.id) {
                widget.start()
            }
            return true
        } catch {
            logger.warning("Hot-load failed for \(record.id): \(error.localizedDescription)")
            return false
        }
    }

    private func startWidgets(for pluginID: String, in registry: WidgetRegistry, loader: DylibPluginLoader) {
        let widgets = registry.leftWidgets + registry.centerWidgets + registry.rightWidgets
        let pluginWidgetIDs = Set(loader.widgetIDs(for: pluginID))
        for widget in widgets where pluginWidgetIDs.contains(widget.id) {
            widget.start()
        }
    }

    static func bundleURL(for record: InstalledPluginRecord) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar/plugins")
            .appendingPathComponent("\(record.bundleName).statusplugin")
    }
}
