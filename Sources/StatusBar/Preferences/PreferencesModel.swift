import Foundation
import StatusBarKit
import SwiftUI

// MARK: - PreferencesModel

@MainActor
@Observable
final class PreferencesModel: ThemeProvider {
    static let shared = PreferencesModel()

    /// Monotonically increasing counter; any preference change bumps this so
    /// SwiftUI views that read `revision` re-evaluate their bodies.
    var revision: Int = 0
    private var suppressDepth = 0
    func bump() {
        guard suppressDepth == 0 else {
            return
        }
        revision += 1
    }

    /// Batch-assign multiple properties with a single `bump()` at the end.
    /// Safe to nest: only the outermost call triggers a `bump()`.
    func applyBatch(_ block: () -> Void) {
        suppressDepth += 1
        defer {
            suppressDepth -= 1
            if suppressDepth == 0 {
                revision += 1
            }
        }
        block()
    }

    // MARK: - General (Bar Dimensions)

    var barHeight: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var barCornerRadius: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var barMargin: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var barYOffset: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var widgetSpacing: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var widgetPaddingH: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Appearance (Colors & Opacity)

    var accentHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var textPrimaryOpacity: Double {
        didSet { scheduleFlush(); bump() }
    }

    var textSecondaryOpacity: Double {
        didSet { scheduleFlush(); bump() }
    }

    var textTertiaryOpacity: Double {
        didSet { scheduleFlush(); bump() }
    }

    var greenHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var yellowHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var redHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var cyanHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var purpleHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Typography

    var iconFontSize: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var labelFontSize: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var smallFontSize: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var monoFontSize: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Graphs

    var graphWidth: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var graphHeight: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var graphDataPoints: Int {
        didSet { scheduleFlush(); bump() }
    }

    var cpuGraphHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var memoryGraphHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Glass Tint

    var barTintHex: UInt32 {
        didSet { scheduleFlush(); bump() }
    }

    var barTintOpacity: Double {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Shadow

    var shadowEnabled: Bool {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Popup

    var popupCornerRadius: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    var popupPadding: CGFloat {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Behavior

    var autoHideEnabled: Bool {
        didSet { scheduleFlush(); bump() }
    }

    var autoHideDwellTime: Double {
        didSet { scheduleFlush(); bump() }
    }

    var autoHideFadeDuration: Double {
        didSet { scheduleFlush(); bump() }
    }

    var launchAtLogin: Bool {
        didSet { scheduleFlush(); bump() }
    }

    var hideInFullscreen: Bool {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Notifications

    var notifyBatteryLow: Bool {
        didSet { scheduleFlush(); bump() }
    }

    var batteryThreshold: Double {
        didSet { scheduleFlush(); bump() }
    }

    var notifyCPUHigh: Bool {
        didSet { scheduleFlush(); bump() }
    }

    var cpuThreshold: Double {
        didSet { scheduleFlush(); bump() }
    }

    var cpuSustainedDuration: Double {
        didSet { scheduleFlush(); bump() }
    }

    var notifyMemoryHigh: Bool {
        didSet { scheduleFlush(); bump() }
    }

    var memoryThreshold: Double {
        didSet { scheduleFlush(); bump() }
    }

    var memorySustainedDuration: Double {
        didSet { scheduleFlush(); bump() }
    }

    var notifyBluetoothBatteryLow: Bool {
        didSet { scheduleFlush(); bump() }
    }

    var bluetoothBatteryThreshold: Double {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Developer

    var devModeEnabled: Bool {
        didSet { scheduleFlush(); bump() }
    }

    // MARK: - Computed Colors

    var accentColor: Color {
        Color(hex: accentHex)
    }

    var primaryColor: Color {
        Color.white.opacity(textPrimaryOpacity)
    }

    var secondaryColor: Color {
        Color.white.opacity(textSecondaryOpacity)
    }

    var tertiaryColor: Color {
        Color.white.opacity(textTertiaryOpacity)
    }

    var greenColor: Color {
        Color(hex: greenHex)
    }

    var yellowColor: Color {
        Color(hex: yellowHex)
    }

    var redColor: Color {
        Color(hex: redHex)
    }

    var cyanColor: Color {
        Color(hex: cyanHex)
    }

    var purpleColor: Color {
        Color(hex: purpleHex)
    }

    var cpuGraphColor: Color {
        Color(hex: cpuGraphHex)
    }

    var memoryGraphColor: Color {
        Color(hex: memoryGraphHex)
    }

    // MARK: - Computed Fonts

    var sfIconFont: Font {
        Font.system(size: iconFontSize, weight: .medium, design: .rounded)
    }

    var labelFont: Font {
        Font.system(size: labelFontSize, weight: .medium)
    }

    var smallFont: Font {
        Font.system(size: smallFontSize, weight: .regular)
    }

    var monoFont: Font {
        Font.system(size: monoFontSize, weight: .medium, design: .monospaced)
    }

    var popupLabelFont: Font {
        Font.system(size: labelFontSize, weight: .regular)
    }

    // MARK: - Init

    /// Initialized with Defaults values. ConfigLoader.bootstrap() will call
    /// `applyBatch` immediately after to overwrite with YAML values.
    private init() {
        let d = Defaults.self
        barHeight = d.barHeight
        barCornerRadius = d.barCornerRadius
        barMargin = d.barMargin
        barYOffset = d.barYOffset
        widgetSpacing = d.widgetSpacing
        widgetPaddingH = d.widgetPaddingH

        accentHex = d.accentHex
        textPrimaryOpacity = d.textPrimaryOpacity
        textSecondaryOpacity = d.textSecondaryOpacity
        textTertiaryOpacity = d.textTertiaryOpacity
        greenHex = d.greenHex
        yellowHex = d.yellowHex
        redHex = d.redHex
        cyanHex = d.cyanHex
        purpleHex = d.purpleHex

        iconFontSize = d.iconFontSize
        labelFontSize = d.labelFontSize
        smallFontSize = d.smallFontSize
        monoFontSize = d.monoFontSize

        graphWidth = d.graphWidth
        graphHeight = d.graphHeight
        graphDataPoints = d.graphDataPoints
        cpuGraphHex = d.cpuGraphHex
        memoryGraphHex = d.memoryGraphHex

        barTintHex = d.barTintHex
        barTintOpacity = d.barTintOpacity

        shadowEnabled = d.shadowEnabled

        popupCornerRadius = d.popupCornerRadius
        popupPadding = d.popupPadding

        autoHideEnabled = d.autoHideEnabled
        autoHideDwellTime = d.autoHideDwellTime
        autoHideFadeDuration = d.autoHideFadeDuration
        launchAtLogin = d.launchAtLogin
        hideInFullscreen = d.hideInFullscreen

        notifyBatteryLow = d.notifyBatteryLow
        batteryThreshold = d.batteryThreshold
        notifyCPUHigh = d.notifyCPUHigh
        cpuThreshold = d.cpuThreshold
        cpuSustainedDuration = d.cpuSustainedDuration
        notifyMemoryHigh = d.notifyMemoryHigh
        memoryThreshold = d.memoryThreshold
        memorySustainedDuration = d.memorySustainedDuration
        notifyBluetoothBatteryLow = d.notifyBluetoothBatteryLow
        bluetoothBatteryThreshold = d.bluetoothBatteryThreshold

        devModeEnabled = d.devModeEnabled
    }

    // MARK: - Reset

    func resetGeneral() {
        applyBatch {
            let d = Defaults.self
            barHeight = d.barHeight
            barCornerRadius = d.barCornerRadius
            barMargin = d.barMargin
            barYOffset = d.barYOffset
            widgetSpacing = d.widgetSpacing
            widgetPaddingH = d.widgetPaddingH
        }
    }

    func resetAppearance() {
        applyBatch {
            let d = Defaults.self
            accentHex = d.accentHex
            textPrimaryOpacity = d.textPrimaryOpacity
            textSecondaryOpacity = d.textSecondaryOpacity
            textTertiaryOpacity = d.textTertiaryOpacity
            greenHex = d.greenHex
            yellowHex = d.yellowHex
            redHex = d.redHex
            cyanHex = d.cyanHex
            purpleHex = d.purpleHex
            barTintHex = d.barTintHex
            barTintOpacity = d.barTintOpacity
            shadowEnabled = d.shadowEnabled
            popupCornerRadius = d.popupCornerRadius
            popupPadding = d.popupPadding
        }
    }

    func resetTypography() {
        applyBatch {
            let d = Defaults.self
            iconFontSize = d.iconFontSize
            labelFontSize = d.labelFontSize
            smallFontSize = d.smallFontSize
            monoFontSize = d.monoFontSize
        }
    }

    func resetGraphs() {
        applyBatch {
            let d = Defaults.self
            graphWidth = d.graphWidth
            graphHeight = d.graphHeight
            graphDataPoints = d.graphDataPoints
            cpuGraphHex = d.cpuGraphHex
            memoryGraphHex = d.memoryGraphHex
        }
    }

    func resetBehavior() {
        applyBatch {
            let d = Defaults.self
            autoHideEnabled = d.autoHideEnabled
            autoHideDwellTime = d.autoHideDwellTime
            autoHideFadeDuration = d.autoHideFadeDuration
            launchAtLogin = d.launchAtLogin
            hideInFullscreen = d.hideInFullscreen
        }
    }

    func resetNotifications() {
        applyBatch {
            let d = Defaults.self
            notifyBatteryLow = d.notifyBatteryLow
            batteryThreshold = d.batteryThreshold
            notifyCPUHigh = d.notifyCPUHigh
            cpuThreshold = d.cpuThreshold
            cpuSustainedDuration = d.cpuSustainedDuration
            notifyMemoryHigh = d.notifyMemoryHigh
            memoryThreshold = d.memoryThreshold
            memorySustainedDuration = d.memorySustainedDuration
            notifyBluetoothBatteryLow = d.notifyBluetoothBatteryLow
            bluetoothBatteryThreshold = d.bluetoothBatteryThreshold
        }
    }

    func resetAll() {
        applyBatch {
            resetGeneral()
            resetAppearance()
            resetTypography()
            resetGraphs()
            resetBehavior()
            resetNotifications()
            devModeEnabled = Defaults.devModeEnabled
        }
    }

    // MARK: - Preset Snapshot

    func snapshot(
        layout: [WidgetLayoutEntry],
        widgetSettings: [String: [String: ConfigValue]] = [:]
    ) -> PresetSnapshot {
        PresetSnapshot(
            barHeight: Double(barHeight),
            barCornerRadius: Double(barCornerRadius),
            barMargin: Double(barMargin),
            barYOffset: Double(barYOffset),
            widgetSpacing: Double(widgetSpacing),
            widgetPaddingH: Double(widgetPaddingH),
            accentHex: accentHex,
            textPrimaryOpacity: textPrimaryOpacity,
            textSecondaryOpacity: textSecondaryOpacity,
            textTertiaryOpacity: textTertiaryOpacity,
            greenHex: greenHex,
            yellowHex: yellowHex,
            redHex: redHex,
            cyanHex: cyanHex,
            purpleHex: purpleHex,
            barTintHex: barTintHex,
            barTintOpacity: barTintOpacity,
            shadowEnabled: shadowEnabled,
            popupCornerRadius: Double(popupCornerRadius),
            popupPadding: Double(popupPadding),
            iconFontSize: Double(iconFontSize),
            labelFontSize: Double(labelFontSize),
            smallFontSize: Double(smallFontSize),
            monoFontSize: Double(monoFontSize),
            graphWidth: Double(graphWidth),
            graphHeight: Double(graphHeight),
            graphDataPoints: graphDataPoints,
            cpuGraphHex: cpuGraphHex,
            memoryGraphHex: memoryGraphHex,
            notifyBatteryLow: notifyBatteryLow,
            batteryThreshold: batteryThreshold,
            notifyCPUHigh: notifyCPUHigh,
            cpuThreshold: cpuThreshold,
            cpuSustainedDuration: cpuSustainedDuration,
            notifyMemoryHigh: notifyMemoryHigh,
            memoryThreshold: memoryThreshold,
            memorySustainedDuration: memorySustainedDuration,
            notifyBluetoothBatteryLow: notifyBluetoothBatteryLow,
            bluetoothBatteryThreshold: bluetoothBatteryThreshold,
            widgetLayout: layout,
            widgetSettings: widgetSettings
        )
    }

    func apply(_ s: PresetSnapshot) {
        applyBatch {
            barHeight = CGFloat(s.barHeight)
            barCornerRadius = CGFloat(s.barCornerRadius)
            barMargin = CGFloat(s.barMargin)
            barYOffset = CGFloat(s.barYOffset)
            widgetSpacing = CGFloat(s.widgetSpacing)
            widgetPaddingH = CGFloat(s.widgetPaddingH)
            accentHex = s.accentHex
            textPrimaryOpacity = s.textPrimaryOpacity
            textSecondaryOpacity = s.textSecondaryOpacity
            textTertiaryOpacity = s.textTertiaryOpacity
            greenHex = s.greenHex
            yellowHex = s.yellowHex
            redHex = s.redHex
            cyanHex = s.cyanHex
            purpleHex = s.purpleHex
            barTintHex = s.barTintHex
            barTintOpacity = s.barTintOpacity
            shadowEnabled = s.shadowEnabled
            popupCornerRadius = CGFloat(s.popupCornerRadius)
            popupPadding = CGFloat(s.popupPadding)
            iconFontSize = CGFloat(s.iconFontSize)
            labelFontSize = CGFloat(s.labelFontSize)
            smallFontSize = CGFloat(s.smallFontSize)
            monoFontSize = CGFloat(s.monoFontSize)
            graphWidth = CGFloat(s.graphWidth)
            graphHeight = CGFloat(s.graphHeight)
            graphDataPoints = s.graphDataPoints
            cpuGraphHex = s.cpuGraphHex
            memoryGraphHex = s.memoryGraphHex
            notifyBatteryLow = s.notifyBatteryLow
            batteryThreshold = s.batteryThreshold
            notifyCPUHigh = s.notifyCPUHigh
            cpuThreshold = s.cpuThreshold
            cpuSustainedDuration = s.cpuSustainedDuration
            notifyMemoryHigh = s.notifyMemoryHigh
            memoryThreshold = s.memoryThreshold
            memorySustainedDuration = s.memorySustainedDuration
            notifyBluetoothBatteryLow = s.notifyBluetoothBatteryLow
            bluetoothBatteryThreshold = s.bluetoothBatteryThreshold
        }
    }

    // MARK: - Config Persistence

    private func scheduleFlush() {
        ConfigLoader.shared.scheduleWrite()
    }
}

// MARK: PreferencesModel.Defaults

extension PreferencesModel {
    enum Defaults {
        // General
        static let barHeight: CGFloat = 40
        static let barCornerRadius: CGFloat = 12
        static let barMargin: CGFloat = 8
        static let barYOffset: CGFloat = 4
        static let widgetSpacing: CGFloat = 6
        static let widgetPaddingH: CGFloat = 6

        // Appearance
        static let accentHex: UInt32 = 0x007AFF
        static let textPrimaryOpacity: Double = 1.0
        static let textSecondaryOpacity: Double = 0.55
        static let textTertiaryOpacity: Double = 0.30
        static let greenHex: UInt32 = 0x34C759
        static let yellowHex: UInt32 = 0xFF9F0A
        static let redHex: UInt32 = 0xFF3B30
        static let cyanHex: UInt32 = 0x64D2FF
        static let purpleHex: UInt32 = 0xBF5AF2

        // Typography
        static let iconFontSize: CGFloat = 13
        static let labelFontSize: CGFloat = 13
        static let smallFontSize: CGFloat = 11
        static let monoFontSize: CGFloat = 12

        // Graphs
        static let graphWidth: CGFloat = 30
        static let graphHeight: CGFloat = 14
        static let graphDataPoints: Int = 50
        static let cpuGraphHex: UInt32 = 0x007AFF
        static let memoryGraphHex: UInt32 = 0x34C759

        // Glass Tint
        static let barTintHex: UInt32 = 0x000000
        static let barTintOpacity: Double = 0.0

        /// Shadow
        static let shadowEnabled: Bool = true

        // Popup
        static let popupCornerRadius: CGFloat = 10
        static let popupPadding: CGFloat = 12

        // Behavior
        static let autoHideEnabled: Bool = true
        static let autoHideDwellTime: Double = 0.3
        static let autoHideFadeDuration: Double = 0.2
        static let launchAtLogin: Bool = false
        static let hideInFullscreen: Bool = true

        // Notifications
        static let notifyBatteryLow: Bool = false
        static let batteryThreshold: Double = 20.0
        static let notifyCPUHigh: Bool = false
        static let cpuThreshold: Double = 90.0
        static let cpuSustainedDuration: Double = 5.0
        static let notifyMemoryHigh: Bool = false
        static let memoryThreshold: Double = 90.0
        static let memorySustainedDuration: Double = 5.0
        static let notifyBluetoothBatteryLow: Bool = false
        static let bluetoothBatteryThreshold: Double = 20.0

        /// Developer
        static let devModeEnabled: Bool = false
    }
}
