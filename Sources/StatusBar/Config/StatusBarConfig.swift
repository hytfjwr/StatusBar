import Foundation
import StatusBarKit

// MARK: - StatusBarConfig

struct StatusBarConfig: Codable {
    var global: GlobalConfig
    var widgets: [WidgetLayoutConfig]
    var widgetSettings: [String: [String: ConfigValue]]

    init() {
        global = GlobalConfig()
        widgets = []
        widgetSettings = [:]
    }

    @MainActor
    static func captureCurrentState() -> Self {
        let prefs = PreferencesModel.shared
        var config = Self()
        config.global = GlobalConfig(from: prefs)
        config.widgets = WidgetRegistry.shared.layout.map { WidgetLayoutConfig(from: $0) }
        config.widgetSettings = WidgetConfigRegistry.shared.exportAll()
        return config
    }
}

// MARK: - GlobalConfig

struct GlobalConfig: Codable {
    var bar: BarConfig
    var appearance: AppearanceConfig
    var typography: TypographyConfig
    var graphs: GraphsConfig
    var behavior: BehaviorConfig
    var notifications: NotificationsConfig

    init() {
        bar = BarConfig()
        appearance = AppearanceConfig()
        typography = TypographyConfig()
        graphs = GraphsConfig()
        behavior = BehaviorConfig()
        notifications = NotificationsConfig()
    }

    @MainActor
    init(from prefs: PreferencesModel) {
        bar = BarConfig(from: prefs)
        appearance = AppearanceConfig(from: prefs)
        typography = TypographyConfig(from: prefs)
        graphs = GraphsConfig(from: prefs)
        behavior = BehaviorConfig(from: prefs)
        notifications = NotificationsConfig(from: prefs)
    }

    @MainActor
    func apply(to prefs: PreferencesModel) {
        bar.apply(to: prefs)
        appearance.apply(to: prefs)
        typography.apply(to: prefs)
        graphs.apply(to: prefs)
        behavior.apply(to: prefs)
        notifications.apply(to: prefs)
    }
}

// MARK: - BarConfig

struct BarConfig: Codable {
    var height: Double
    var cornerRadius: Double
    var margin: Double
    var yOffset: Double
    var widgetSpacing: Double
    var widgetPaddingH: Double

    init() {
        let d = PreferencesModel.Defaults.self
        height = Double(d.barHeight)
        cornerRadius = Double(d.barCornerRadius)
        margin = Double(d.barMargin)
        yOffset = Double(d.barYOffset)
        widgetSpacing = Double(d.widgetSpacing)
        widgetPaddingH = Double(d.widgetPaddingH)
    }

    @MainActor
    init(from p: PreferencesModel) {
        height = Double(p.barHeight)
        cornerRadius = Double(p.barCornerRadius)
        margin = Double(p.barMargin)
        yOffset = Double(p.barYOffset)
        widgetSpacing = Double(p.widgetSpacing)
        widgetPaddingH = Double(p.widgetPaddingH)
    }

    @MainActor
    func apply(to p: PreferencesModel) {
        p.barHeight = CGFloat(height)
        p.barCornerRadius = CGFloat(cornerRadius)
        p.barMargin = CGFloat(margin)
        p.barYOffset = CGFloat(yOffset)
        p.widgetSpacing = CGFloat(widgetSpacing)
        p.widgetPaddingH = CGFloat(widgetPaddingH)
    }
}

// MARK: - AppearanceConfig

struct AppearanceConfig: Codable {
    var accent: HexColor
    var textPrimaryOpacity: Double
    var textSecondaryOpacity: Double
    var textTertiaryOpacity: Double
    var green: HexColor
    var yellow: HexColor
    var red: HexColor
    var cyan: HexColor
    var purple: HexColor
    var barTint: HexColor
    var barTintOpacity: Double
    var shadowEnabled: Bool
    var popupCornerRadius: Double
    var popupPadding: Double

    init() {
        let d = PreferencesModel.Defaults.self
        accent = HexColor(d.accentHex)
        textPrimaryOpacity = d.textPrimaryOpacity
        textSecondaryOpacity = d.textSecondaryOpacity
        textTertiaryOpacity = d.textTertiaryOpacity
        green = HexColor(d.greenHex)
        yellow = HexColor(d.yellowHex)
        red = HexColor(d.redHex)
        cyan = HexColor(d.cyanHex)
        purple = HexColor(d.purpleHex)
        barTint = HexColor(d.barTintHex)
        barTintOpacity = d.barTintOpacity
        shadowEnabled = d.shadowEnabled
        popupCornerRadius = Double(d.popupCornerRadius)
        popupPadding = Double(d.popupPadding)
    }

    @MainActor
    init(from p: PreferencesModel) {
        accent = HexColor(p.accentHex)
        textPrimaryOpacity = p.textPrimaryOpacity
        textSecondaryOpacity = p.textSecondaryOpacity
        textTertiaryOpacity = p.textTertiaryOpacity
        green = HexColor(p.greenHex)
        yellow = HexColor(p.yellowHex)
        red = HexColor(p.redHex)
        cyan = HexColor(p.cyanHex)
        purple = HexColor(p.purpleHex)
        barTint = HexColor(p.barTintHex)
        barTintOpacity = p.barTintOpacity
        shadowEnabled = p.shadowEnabled
        popupCornerRadius = Double(p.popupCornerRadius)
        popupPadding = Double(p.popupPadding)
    }

    @MainActor
    func apply(to p: PreferencesModel) {
        p.accentHex = accent.rawValue
        p.textPrimaryOpacity = textPrimaryOpacity
        p.textSecondaryOpacity = textSecondaryOpacity
        p.textTertiaryOpacity = textTertiaryOpacity
        p.greenHex = green.rawValue
        p.yellowHex = yellow.rawValue
        p.redHex = red.rawValue
        p.cyanHex = cyan.rawValue
        p.purpleHex = purple.rawValue
        p.barTintHex = barTint.rawValue
        p.barTintOpacity = barTintOpacity
        p.shadowEnabled = shadowEnabled
        p.popupCornerRadius = CGFloat(popupCornerRadius)
        p.popupPadding = CGFloat(popupPadding)
    }
}

// MARK: - TypographyConfig

struct TypographyConfig: Codable {
    var iconFontSize: Double
    var labelFontSize: Double
    var smallFontSize: Double
    var monoFontSize: Double

    init() {
        let d = PreferencesModel.Defaults.self
        iconFontSize = Double(d.iconFontSize)
        labelFontSize = Double(d.labelFontSize)
        smallFontSize = Double(d.smallFontSize)
        monoFontSize = Double(d.monoFontSize)
    }

    @MainActor
    init(from p: PreferencesModel) {
        iconFontSize = Double(p.iconFontSize)
        labelFontSize = Double(p.labelFontSize)
        smallFontSize = Double(p.smallFontSize)
        monoFontSize = Double(p.monoFontSize)
    }

    @MainActor
    func apply(to p: PreferencesModel) {
        p.iconFontSize = CGFloat(iconFontSize)
        p.labelFontSize = CGFloat(labelFontSize)
        p.smallFontSize = CGFloat(smallFontSize)
        p.monoFontSize = CGFloat(monoFontSize)
    }
}

// MARK: - GraphsConfig

struct GraphsConfig: Codable {
    var width: Double
    var height: Double
    var dataPoints: Int
    var cpuColor: HexColor
    var memoryColor: HexColor

    init() {
        let d = PreferencesModel.Defaults.self
        width = Double(d.graphWidth)
        height = Double(d.graphHeight)
        dataPoints = d.graphDataPoints
        cpuColor = HexColor(d.cpuGraphHex)
        memoryColor = HexColor(d.memoryGraphHex)
    }

    @MainActor
    init(from p: PreferencesModel) {
        width = Double(p.graphWidth)
        height = Double(p.graphHeight)
        dataPoints = p.graphDataPoints
        cpuColor = HexColor(p.cpuGraphHex)
        memoryColor = HexColor(p.memoryGraphHex)
    }

    @MainActor
    func apply(to p: PreferencesModel) {
        p.graphWidth = CGFloat(width)
        p.graphHeight = CGFloat(height)
        p.graphDataPoints = dataPoints
        p.cpuGraphHex = cpuColor.rawValue
        p.memoryGraphHex = memoryColor.rawValue
    }
}

// MARK: - BehaviorConfig

struct BehaviorConfig: Codable {
    var autoHide: Bool
    var autoHideDwellTime: Double
    var autoHideFadeDuration: Double
    var launchAtLogin: Bool

    init() {
        let d = PreferencesModel.Defaults.self
        autoHide = d.autoHideEnabled
        autoHideDwellTime = d.autoHideDwellTime
        autoHideFadeDuration = d.autoHideFadeDuration
        launchAtLogin = d.launchAtLogin
    }

    @MainActor
    init(from p: PreferencesModel) {
        autoHide = p.autoHideEnabled
        autoHideDwellTime = p.autoHideDwellTime
        autoHideFadeDuration = p.autoHideFadeDuration
        launchAtLogin = p.launchAtLogin
    }

    @MainActor
    func apply(to p: PreferencesModel) {
        p.autoHideEnabled = autoHide
        p.autoHideDwellTime = autoHideDwellTime
        p.autoHideFadeDuration = autoHideFadeDuration
        p.launchAtLogin = launchAtLogin
    }
}

// MARK: - NotificationsConfig

struct NotificationsConfig: Codable {
    var batteryLow: Bool
    var batteryThreshold: Double
    var cpuHigh: Bool
    var cpuThreshold: Double
    var cpuSustainedDuration: Double
    var memoryHigh: Bool
    var memoryThreshold: Double
    var memorySustainedDuration: Double

    init() {
        let d = PreferencesModel.Defaults.self
        batteryLow = d.notifyBatteryLow
        batteryThreshold = d.batteryThreshold
        cpuHigh = d.notifyCPUHigh
        cpuThreshold = d.cpuThreshold
        cpuSustainedDuration = d.cpuSustainedDuration
        memoryHigh = d.notifyMemoryHigh
        memoryThreshold = d.memoryThreshold
        memorySustainedDuration = d.memorySustainedDuration
    }

    @MainActor
    init(from p: PreferencesModel) {
        batteryLow = p.notifyBatteryLow
        batteryThreshold = p.batteryThreshold
        cpuHigh = p.notifyCPUHigh
        cpuThreshold = p.cpuThreshold
        cpuSustainedDuration = p.cpuSustainedDuration
        memoryHigh = p.notifyMemoryHigh
        memoryThreshold = p.memoryThreshold
        memorySustainedDuration = p.memorySustainedDuration
    }

    @MainActor
    func apply(to p: PreferencesModel) {
        p.notifyBatteryLow = batteryLow
        p.batteryThreshold = batteryThreshold
        p.notifyCPUHigh = cpuHigh
        p.cpuThreshold = cpuThreshold
        p.cpuSustainedDuration = cpuSustainedDuration
        p.notifyMemoryHigh = memoryHigh
        p.memoryThreshold = memoryThreshold
        p.memorySustainedDuration = memorySustainedDuration
    }
}

// MARK: - WidgetLayoutConfig

struct WidgetLayoutConfig: Codable {
    var id: String
    var section: WidgetPosition
    var sortIndex: Int
    var visible: Bool

    init(from entry: WidgetLayoutEntry) {
        id = entry.id
        section = entry.section
        sortIndex = entry.sortIndex
        visible = entry.isVisible
    }

    var asEntry: WidgetLayoutEntry {
        WidgetLayoutEntry(id: id, section: section, sortIndex: sortIndex, isVisible: visible)
    }
}
