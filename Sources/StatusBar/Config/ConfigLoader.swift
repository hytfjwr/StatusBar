import Foundation
import OSLog
import ServiceManagement
import StatusBarKit
import Yams

extension IPCEventEnvelope {
    static func configReloaded() -> Self {
        IPCEventEnvelope(event: BarEvent.configReloaded)
    }
}

private let logger = Logger(subsystem: "com.statusbar", category: "ConfigLoader")

extension Notification.Name {
    static let configParseError = Notification.Name("ConfigParseError")
}

// MARK: - ConfigLoader

@MainActor
final class ConfigLoader {
    static let shared = ConfigLoader()

    /// The loaded config. Available after `bootstrap()`.
    private(set) var currentConfig = StatusBarConfig()

    private let fileURL: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private var writeTask: Task<Void, Never>?

    /// Timestamp of our last write; FS events within the grace period are ignored.
    private var lastWriteTime: Date?

    /// Grace period after a write during which FS events are ignored.
    private let writeGracePeriod: TimeInterval = 0.5

    /// Last known modification date of config.yml, used to skip redundant reloads.
    private var lastKnownConfigModDate: Date?

    /// Guards against write-back during apply (hot-reload or bootstrap).
    private var isApplying = false

    /// True when bootstrap created a fresh config (no existing file).
    private(set) var isFirstLaunch = false

    private init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar", isDirectory: true)
        fileURL = configDir.appendingPathComponent("config.yml")
    }

    // MARK: - Bootstrap

    /// Call once from `AppDelegate`, before `Theme.configure`.
    func bootstrap() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            currentConfig = try loadConfigFromDisk()
            // Record initial modification date so the FS watcher can skip
            // events where config.yml hasn't actually changed.
            // swiftformat:disable:next redundantSelf
            if let attrs = try? fm.attributesOfItem(atPath: self.fileURL.path),
               let modDate = attrs[.modificationDate] as? Date
            {
                lastKnownConfigModDate = modDate
            }
            // swiftformat:disable:next redundantSelf
            logger.info("Loaded config from \(self.fileURL.path)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError
        {
            isFirstLaunch = true
            currentConfig = StatusBarConfig()
            writeCurrentStateToDisk()
            // swiftformat:disable:next redundantSelf
            logger.info("Generated default config at \(self.fileURL.path)")
        } catch {
            logger.error("Failed to load config, using defaults: \(error.localizedDescription)")
            currentConfig = StatusBarConfig()
            writeCurrentStateToDisk()
        }

        // Populate the widget config registry so Settings singletons can read initial values
        WidgetConfigRegistry.shared.setLoadedConfig(currentConfig.widgetSettings)

        // Wire the registry's write-back callback
        WidgetConfigRegistry.shared.onSettingsChanged = { [weak self] in
            self?.scheduleWrite()
        }

        applyToLiveModels()
        startWatching()
    }

    // MARK: - YAML I/O

    /// Maximum config file size (1 MB) to prevent resource exhaustion (e.g. YAML billion laughs).
    private static let maxConfigFileSize: UInt64 = 1_048_576

    /// Synchronous file I/O. Called during bootstrap (before run loop) and hot-reload
    /// (small YAML file, sub-millisecond). Kept synchronous intentionally.
    private func loadConfigFromDisk() throws -> StatusBarConfig {
        // Check file size before reading to prevent resource exhaustion
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attrs[.size] as? UInt64 ?? 0
        guard fileSize <= Self.maxConfigFileSize else {
            throw NSError(
                domain: "ConfigLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Config file exceeds 1 MB size limit"]
            )
        }

        let data = try Data(contentsOf: fileURL)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        return try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)
    }

    // MARK: - Apply config to live models

    private func applyToLiveModels() {
        isApplying = true
        defer { isApplying = false }

        let prefs = PreferencesModel.shared
        prefs.applyBatch {
            currentConfig.global.apply(to: prefs)
        }

        // Sync launchAtLogin YAML value with SMAppService system state
        LaunchAtLoginService.setEnabled(prefs.launchAtLogin)

        // Update registry data and apply to all registered widget settings providers
        WidgetConfigRegistry.shared.setLoadedConfig(currentConfig.widgetSettings)
        WidgetConfigRegistry.shared.applyToAll()
    }

    /// Apply layout from config. Called after all widgets are registered.
    func applyLayoutIfNeeded() {
        guard !currentConfig.widgets.isEmpty else {
            return
        }
        let entries = currentConfig.widgets.map(\.asEntry)
        WidgetRegistry.shared.applyLayout(entries)
    }

    // MARK: - Write

    /// Debounced write — called by PreferencesModel/WidgetRegistry/Settings on change.
    func scheduleWrite() {
        guard !isApplying else {
            return
        }
        writeTask?.cancel()
        writeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            self?.captureAndWrite()
        }
    }

    private func captureAndWrite() {
        currentConfig = StatusBarConfig.captureCurrentState()
        writeCurrentStateToDisk()
    }

    private func writeCurrentStateToDisk() {
        lastWriteTime = Date()

        do {
            let encoder = YAMLEncoder()
            let rawYAML = try encoder.encode(currentConfig)
            let yamlString = Self.fixScientificNotation(rawYAML)
            let data = Data(yamlString.utf8)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to write config: \(error.localizedDescription)")
        }
    }

    // MARK: - YAML Number Formatting

    /// Replace scientific notation (e.g. `4e+1`, `5.5e-1`) with human-readable decimals.
    nonisolated static func fixScientificNotation(_ yaml: String) -> String {
        let pattern = /(-?\d+\.?\d*)[eE]([+-]?\d+)/
        return yaml.replacing(pattern) { match in
            let baseStr = String(match.output.1)
            let expStr = String(match.output.2)
            guard let base = Double(baseStr), let exp = Int(expStr) else {
                return "\(match.output.0)"[...]
            }
            let value = base * pow(10.0, Double(exp))
            if value == value.rounded(.towardZero), value.magnitude < 1e15 {
                return Substring(String(format: "%.0f", value))
            }
            var str = String(format: "%.10f", value)
            while str.hasSuffix("0"), !str.hasSuffix(".0") {
                str.removeLast()
            }
            return Substring(str)
        }
    }

    // MARK: - FSEvents File Watching

    private func startWatching() {
        let dirPath = fileURL.deletingLastPathComponent().path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("Failed to open config directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleFileSystemEvent()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fsSource = source
        logger.info("Watching config directory for changes")
    }

    private func handleFileSystemEvent() {
        // Ignore FS events that arrive shortly after our own writes
        if let lastWrite = lastWriteTime,
           Date().timeIntervalSince(lastWrite) < writeGracePeriod
        {
            return
        }

        // Check if config.yml itself actually changed (ignore temp/plugin file changes)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return
        }
        if let lastMod = lastKnownConfigModDate, modDate <= lastMod {
            return // config.yml unchanged
        }

        do {
            let newConfig = try loadConfigFromDisk()
            lastKnownConfigModDate = modDate
            applyNewConfig(newConfig)
            logger.info("Config hot-reloaded")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError
        {
            // File was deleted — ignore
        } catch {
            logger.error("Config hot-reload failed: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .configParseError,
                object: nil,
                userInfo: ["message": error.localizedDescription]
            )
        }
    }

    // MARK: - Reload (called by IPC)

    /// Reload configuration from disk.
    func reloadFromDisk() {
        let fm = FileManager.default
        do {
            let newConfig = try loadConfigFromDisk()
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date
            {
                lastKnownConfigModDate = modDate
            }
            applyNewConfig(newConfig)
            logger.info("Config reloaded via IPC")
        } catch {
            logger.error("Config reload via IPC failed: \(error.localizedDescription)")
        }
    }

    /// Shared logic for applying a newly loaded config.
    private func applyNewConfig(_ newConfig: StatusBarConfig) {
        currentConfig = newConfig
        applyToLiveModels()

        if !newConfig.widgets.isEmpty {
            let entries = newConfig.widgets.map(\.asEntry)
            WidgetRegistry.shared.applyLayout(entries)
        }

        EventBus.shared.emit(.configReloaded())
    }

    // MARK: - Teardown

    func teardown() {
        fsSource?.cancel()
        fsSource = nil
        writeTask?.cancel()
        writeTask = nil
    }
}
