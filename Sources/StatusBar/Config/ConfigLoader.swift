import Foundation
import OSLog
import StatusBarKit
import Yams

private let logger = Logger(subsystem: "com.statusbar", category: "ConfigLoader")

@MainActor
final class ConfigLoader {
    static let shared = ConfigLoader()

    /// The loaded config. Available after `bootstrap()`.
    private(set) var currentConfig = StatusBarConfig()

    private let fileURL: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private var writeTask: Task<Void, Never>?

    /// Guards against reloading a file we just wrote ourselves.
    private var isWriting = false

    /// Guards against write-back during apply (hot-reload or bootstrap).
    private var isApplying = false

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
            logger.info("Loaded config from \(self.fileURL.path)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            currentConfig = StatusBarConfig()
            writeCurrentStateToDisk()
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

    private nonisolated func loadConfigFromDisk() throws -> StatusBarConfig {
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

        // Update registry data and apply to all registered widget settings providers
        WidgetConfigRegistry.shared.setLoadedConfig(currentConfig.widgetSettings)
        WidgetConfigRegistry.shared.applyToAll()
    }

    /// Apply layout from config. Called after all widgets are registered.
    func applyLayoutIfNeeded() {
        guard !currentConfig.widgets.isEmpty else { return }
        let entries = currentConfig.widgets.map(\.asEntry)
        WidgetRegistry.shared.applyLayout(entries)
    }

    // MARK: - Write

    /// Debounced write — called by PreferencesModel/WidgetRegistry/Settings on change.
    func scheduleWrite() {
        guard !isApplying else { return }
        writeTask?.cancel()
        writeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.captureAndWrite()
        }
    }

    private func captureAndWrite() {
        currentConfig = StatusBarConfig.captureCurrentState()
        writeCurrentStateToDisk()
    }

    private func writeCurrentStateToDisk() {
        isWriting = true
        defer {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.isWriting = false
            }
        }

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
    private static func fixScientificNotation(_ yaml: String) -> String {
        let pattern = /(-?\d+\.?\d*)[eE]([+-]?\d+)/
        return yaml.replacing(pattern) { match in
            let baseStr = String(match.output.1)
            let expStr = String(match.output.2)
            guard let base = Double(baseStr), let exp = Int(expStr) else {
                return "\(match.output.0)"[...]
            }
            let value = base * pow(10.0, Double(exp))
            if value == value.rounded(.towardZero) && value.magnitude < 1e15 {
                return Substring(String(format: "%.0f", value))
            }
            var str = String(format: "%.10f", value)
            while str.hasSuffix("0") && !str.hasSuffix(".0") {
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
        guard !isWriting else { return }

        do {
            let newConfig = try loadConfigFromDisk()
            currentConfig = newConfig
            applyToLiveModels()

            if !newConfig.widgets.isEmpty {
                let entries = newConfig.widgets.map(\.asEntry)
                WidgetRegistry.shared.applyLayout(entries)
            }

            logger.info("Config hot-reloaded")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            // File was deleted — ignore
        } catch {
            logger.error("Config hot-reload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Teardown

    func teardown() {
        fsSource?.cancel()
        fsSource = nil
        writeTask?.cancel()
        writeTask = nil
    }
}
