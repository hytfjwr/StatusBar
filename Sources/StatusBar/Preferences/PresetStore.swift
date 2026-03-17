import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "PresetStore")

// MARK: - PresetSnapshot

/// A complete, point-in-time capture of all user-configurable state.
/// All field names intentionally match the UserDefaults keys used by PreferencesModel.
struct PresetSnapshot: Codable, Sendable {
    // General
    var barHeight: Double
    var barCornerRadius: Double
    var barMargin: Double
    var barYOffset: Double
    var widgetSpacing: Double
    var widgetPaddingH: Double

    // Appearance
    var accentHex: UInt32
    var textPrimaryOpacity: Double
    var textSecondaryOpacity: Double
    var textTertiaryOpacity: Double
    var greenHex: UInt32
    var yellowHex: UInt32
    var redHex: UInt32
    var cyanHex: UInt32
    var purpleHex: UInt32
    var barTintHex: UInt32
    var barTintOpacity: Double
    var shadowEnabled: Bool
    var popupCornerRadius: Double
    var popupPadding: Double

    // Typography
    var iconFontSize: Double
    var labelFontSize: Double
    var smallFontSize: Double
    var monoFontSize: Double

    // Graphs
    var graphWidth: Double
    var graphHeight: Double
    var graphDataPoints: Int
    var cpuGraphHex: UInt32
    var memoryGraphHex: UInt32

    // Widget Layout
    var widgetLayout: [WidgetLayoutEntry]
}

extension PresetSnapshot {
    /// Capture current live state from PreferencesModel + WidgetRegistry.
    @MainActor
    static func captureCurrentState() -> PresetSnapshot {
        PreferencesModel.shared.snapshot(layout: WidgetRegistry.shared.layout)
    }
}

// MARK: - Built-in Snapshots

extension PresetSnapshot {
    static var `default`: PresetSnapshot {
        let d = PreferencesModel.Defaults.self
        return PresetSnapshot(
            barHeight: Double(d.barHeight),
            barCornerRadius: Double(d.barCornerRadius),
            barMargin: Double(d.barMargin),
            barYOffset: Double(d.barYOffset),
            widgetSpacing: Double(d.widgetSpacing),
            widgetPaddingH: Double(d.widgetPaddingH),
            accentHex: d.accentHex,
            textPrimaryOpacity: d.textPrimaryOpacity,
            textSecondaryOpacity: d.textSecondaryOpacity,
            textTertiaryOpacity: d.textTertiaryOpacity,
            greenHex: d.greenHex,
            yellowHex: d.yellowHex,
            redHex: d.redHex,
            cyanHex: d.cyanHex,
            purpleHex: d.purpleHex,
            barTintHex: d.barTintHex,
            barTintOpacity: d.barTintOpacity,
            shadowEnabled: d.shadowEnabled,
            popupCornerRadius: Double(d.popupCornerRadius),
            popupPadding: Double(d.popupPadding),
            iconFontSize: Double(d.iconFontSize),
            labelFontSize: Double(d.labelFontSize),
            smallFontSize: Double(d.smallFontSize),
            monoFontSize: Double(d.monoFontSize),
            graphWidth: Double(d.graphWidth),
            graphHeight: Double(d.graphHeight),
            graphDataPoints: d.graphDataPoints,
            cpuGraphHex: d.cpuGraphHex,
            memoryGraphHex: d.memoryGraphHex,
            widgetLayout: []  // empty = reset to registry default
        )
    }

    static var minimal: PresetSnapshot {
        var s = Self.default
        s.barHeight = 34
        s.barCornerRadius = 8
        s.barMargin = 6
        s.widgetSpacing = 4
        s.widgetPaddingH = 4
        s.barTintOpacity = 0.0
        s.shadowEnabled = false
        s.textSecondaryOpacity = 0.4
        s.textTertiaryOpacity = 0.2
        s.iconFontSize = 12
        s.labelFontSize = 12
        s.smallFontSize = 10
        s.monoFontSize = 11
        s.graphWidth = 24
        s.graphHeight = 12
        return s
    }

    static var colorful: PresetSnapshot {
        var s = Self.default
        s.accentHex = 0xFF6B6B
        s.greenHex = 0x6BCB77
        s.yellowHex = 0xFFD93D
        s.redHex = 0xFF6B6B
        s.cyanHex = 0x4ECDC4
        s.purpleHex = 0xC77DFF
        s.cpuGraphHex = 0xFF6B6B
        s.memoryGraphHex = 0x6BCB77
        s.barTintHex = 0x1A1A2E
        s.barTintOpacity = 0.3
        return s
    }
}

// MARK: - Preset

struct Preset: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let isBuiltIn: Bool
    let createdAt: Date
    var snapshot: PresetSnapshot

    init(id: UUID = UUID(), name: String, isBuiltIn: Bool = false,
         createdAt: Date = Date(), snapshot: PresetSnapshot) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.snapshot = snapshot
    }
}

// MARK: - PresetStore

@MainActor
@Observable
final class PresetStore {
    static let shared = PresetStore()

    private(set) var userPresets: [Preset] = []

    var allPresets: [Preset] {
        Self.builtInPresets + userPresets.sorted { $0.createdAt < $1.createdAt }
    }

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatusBar", isDirectory: true)
        fileURL = appSupport.appendingPathComponent("presets.json")
        loadFromDisk()
    }

    // MARK: - Built-in Presets

    static let builtInPresets: [Preset] = [
        Preset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Default",
            isBuiltIn: true,
            createdAt: .distantPast,
            snapshot: .default
        ),
        Preset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Minimal",
            isBuiltIn: true,
            createdAt: .distantPast,
            snapshot: .minimal
        ),
        Preset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Colorful",
            isBuiltIn: true,
            createdAt: .distantPast,
            snapshot: .colorful
        ),
    ]

    // MARK: - CRUD

    func saveCurrentState(name: String) {
        let snapshot = PresetSnapshot.captureCurrentState()
        let preset = Preset(name: name, snapshot: snapshot)
        userPresets.append(preset)
        persistToDisk()
    }

    func rename(_ preset: Preset, to newName: String) {
        guard !preset.isBuiltIn,
              let idx = userPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        userPresets[idx].name = newName
        persistToDisk()
    }

    func delete(_ preset: Preset) {
        guard !preset.isBuiltIn else { return }
        userPresets.removeAll { $0.id == preset.id }
        persistToDisk()
    }

    func deleteAllUserPresets() {
        userPresets.removeAll()
        persistToDisk()
    }

    // MARK: - Apply

    func apply(_ preset: Preset) {
        let snapshot = preset.snapshot
        PreferencesModel.shared.apply(snapshot)
        if snapshot.widgetLayout.isEmpty {
            WidgetRegistry.shared.resetLayout()
        } else {
            WidgetRegistry.shared.applyLayout(snapshot.widgetLayout)
        }
    }

    // MARK: - Export

    func exportData(_ preset: Preset) -> Data? {
        let encoder = Self.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(preset)
        } catch {
            logger.warning("Failed to export preset '\(preset.name)': \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Import

    func importPreset(from data: Data) -> Bool {
        guard let decoded = try? Self.makeDecoder().decode(Preset.self, from: data) else {
            logger.warning("Failed to decode imported preset data")
            return false
        }
        let preset = Preset(name: decoded.name, snapshot: decoded.snapshot)
        userPresets.append(preset)
        persistToDisk()
        return true
    }

    // MARK: - Persistence

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try Self.makeDecoder().decode([Preset].self, from: data)
            userPresets = decoded.filter { !$0.isBuiltIn }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // First launch — no file yet, expected
        } catch {
            logger.warning("Failed to load presets: \(error.localizedDescription)")
        }
    }

    private func persistToDisk() {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(userPresets)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist presets: \(error.localizedDescription)")
        }
    }
}
