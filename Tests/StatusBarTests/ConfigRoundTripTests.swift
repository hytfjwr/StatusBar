import Foundation
@testable import StatusBar
import Testing
import Yams

struct ConfigRoundTripTests {
    @Test("Default config encodes and decodes via YAML")
    func defaultConfigRoundTrip() throws {
        let original = StatusBarConfig()

        // Encode
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(original)

        // Decode
        let decoded = try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)

        // Verify key fields
        #expect(decoded.global.bar.height == original.global.bar.height)
        #expect(decoded.global.bar.cornerRadius == original.global.bar.cornerRadius)
        #expect(decoded.global.bar.margin == original.global.bar.margin)
        #expect(decoded.global.appearance.accent == original.global.appearance.accent)
        #expect(decoded.global.appearance.shadowEnabled == original.global.appearance.shadowEnabled)
        #expect(decoded.global.typography.iconFontSize == original.global.typography.iconFontSize)
        #expect(decoded.global.graphs.dataPoints == original.global.graphs.dataPoints)
        #expect(decoded.global.behavior.autoHide == original.global.behavior.autoHide)
        #expect(decoded.global.behavior.hideInFullscreen == original.global.behavior.hideInFullscreen)
        #expect(decoded.global.notifications.batteryLow == original.global.notifications.batteryLow)
    }

    @Test("BarConfig preserves all fields through YAML")
    func barConfigRoundTrip() throws {
        var bar = BarConfig()
        bar.height = 50
        bar.cornerRadius = 16
        bar.margin = 10
        bar.yOffset = 5
        bar.widgetSpacing = 8
        bar.widgetPaddingH = 12

        let yaml = try YAMLEncoder().encode(bar)
        let decoded = try YAMLDecoder().decode(BarConfig.self, from: yaml)

        #expect(decoded.height == 50)
        #expect(decoded.cornerRadius == 16)
        #expect(decoded.margin == 10)
        #expect(decoded.yOffset == 5)
        #expect(decoded.widgetSpacing == 8)
        #expect(decoded.widgetPaddingH == 12)
    }

    @Test("AppearanceConfig preserves HexColor fields")
    func appearanceConfigHexColors() throws {
        var appearance = AppearanceConfig()
        appearance.accent = HexColor(0xFF6B6B)
        appearance.green = HexColor(0x6BCB77)
        appearance.barTintOpacity = 0.3

        let yaml = try YAMLEncoder().encode(appearance)
        let decoded = try YAMLDecoder().decode(AppearanceConfig.self, from: yaml)

        #expect(decoded.accent == HexColor(0xFF6B6B))
        #expect(decoded.green == HexColor(0x6BCB77))
        #expect(decoded.barTintOpacity == 0.3)
    }

    @Test("NotificationsConfig preserves threshold values")
    func notificationsConfigRoundTrip() throws {
        var notifications = NotificationsConfig()
        notifications.batteryLow = true
        notifications.batteryThreshold = 15.0
        notifications.cpuHigh = true
        notifications.cpuThreshold = 90.0
        notifications.cpuSustainedDuration = 30.0

        let yaml = try YAMLEncoder().encode(notifications)
        let decoded = try YAMLDecoder().decode(NotificationsConfig.self, from: yaml)

        #expect(decoded.batteryLow == true)
        #expect(decoded.batteryThreshold == 15.0)
        #expect(decoded.cpuHigh == true)
        #expect(decoded.cpuThreshold == 90.0)
        #expect(decoded.cpuSustainedDuration == 30.0)
    }

    @Test("BehaviorConfig preserves all fields through YAML")
    func behaviorConfigRoundTrip() throws {
        var behavior = BehaviorConfig()
        behavior.autoHide = true
        behavior.autoHideDwellTime = 0.5
        behavior.autoHideFadeDuration = 0.3
        behavior.launchAtLogin = true
        behavior.hideInFullscreen = false

        let yaml = try YAMLEncoder().encode(behavior)
        let decoded = try YAMLDecoder().decode(BehaviorConfig.self, from: yaml)

        #expect(decoded.autoHide == true)
        #expect(decoded.autoHideDwellTime == 0.5)
        #expect(decoded.autoHideFadeDuration == 0.3)
        #expect(decoded.launchAtLogin == true)
        #expect(decoded.hideInFullscreen == false)
    }

    @Test("Empty widget list round-trips correctly")
    func emptyWidgetsRoundTrip() throws {
        var config = StatusBarConfig()
        config.widgets = []
        config.widgetSettings = [:]

        let yaml = try YAMLEncoder().encode(config)
        let decoded = try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)

        #expect(decoded.widgets.isEmpty)
        #expect(decoded.widgetSettings.isEmpty)
    }

    // MARK: - Partial-YAML migration safety

    @Test("BarConfig fills missing fields with defaults")
    func barConfigPartialDecode() throws {
        let yaml = "height: 50\n"
        let decoded = try YAMLDecoder().decode(BarConfig.self, from: yaml)
        let d = PreferencesModel.Defaults.self

        #expect(decoded.height == 50)
        // Missing fields fall back to defaults.
        #expect(decoded.cornerRadius == Double(d.barCornerRadius))
        #expect(decoded.margin == Double(d.barMargin))
        #expect(decoded.yOffset == Double(d.barYOffset))
        #expect(decoded.widgetSpacing == Double(d.widgetSpacing))
        #expect(decoded.widgetPaddingH == Double(d.widgetPaddingH))
    }

    @Test("AppearanceConfig fills missing fields with defaults")
    func appearanceConfigPartialDecode() throws {
        let yaml = "accent: \"#FF00AA\"\nshadowEnabled: false\n"
        let decoded = try YAMLDecoder().decode(AppearanceConfig.self, from: yaml)
        let d = PreferencesModel.Defaults.self

        #expect(decoded.accent == HexColor(0xFF00AA))
        #expect(decoded.shadowEnabled == false)
        // Defaults for omitted fields.
        #expect(decoded.green == HexColor(d.greenHex))
        #expect(decoded.yellow == HexColor(d.yellowHex))
        #expect(decoded.red == HexColor(d.redHex))
        #expect(decoded.barTintOpacity == d.barTintOpacity)
        #expect(decoded.popupCornerRadius == Double(d.popupCornerRadius))
        #expect(decoded.popupPadding == Double(d.popupPadding))
    }

    @Test("BehaviorConfig fills missing fields with defaults")
    func behaviorConfigPartialDecode() throws {
        let yaml = "autoHide: false\n"
        let decoded = try YAMLDecoder().decode(BehaviorConfig.self, from: yaml)
        let d = PreferencesModel.Defaults.self

        #expect(decoded.autoHide == false)
        #expect(decoded.autoHideDwellTime == d.autoHideDwellTime)
        #expect(decoded.autoHideFadeDuration == d.autoHideFadeDuration)
        #expect(decoded.launchAtLogin == d.launchAtLogin)
        #expect(decoded.hideInFullscreen == d.hideInFullscreen)
    }

    @Test("TypographyConfig fills missing fields with defaults")
    func typographyConfigPartialDecode() throws {
        let yaml = "labelFontSize: 16\n"
        let decoded = try YAMLDecoder().decode(TypographyConfig.self, from: yaml)
        let d = PreferencesModel.Defaults.self

        #expect(decoded.labelFontSize == 16)
        #expect(decoded.iconFontSize == Double(d.iconFontSize))
        #expect(decoded.smallFontSize == Double(d.smallFontSize))
        #expect(decoded.monoFontSize == Double(d.monoFontSize))
    }

    @Test("GraphsConfig fills missing fields with defaults")
    func graphsConfigPartialDecode() throws {
        let yaml = "dataPoints: 120\n"
        let decoded = try YAMLDecoder().decode(GraphsConfig.self, from: yaml)
        let d = PreferencesModel.Defaults.self

        #expect(decoded.dataPoints == 120)
        #expect(decoded.width == Double(d.graphWidth))
        #expect(decoded.height == Double(d.graphHeight))
        #expect(decoded.cpuColor == HexColor(d.cpuGraphHex))
        #expect(decoded.memoryColor == HexColor(d.memoryGraphHex))
    }

    @Test("Empty YAML dict decodes each sub-config to full defaults")
    func emptyDictDecodesToDefaults() throws {
        let empty = "{}\n"
        let bar = try YAMLDecoder().decode(BarConfig.self, from: empty)
        let appearance = try YAMLDecoder().decode(AppearanceConfig.self, from: empty)
        let typography = try YAMLDecoder().decode(TypographyConfig.self, from: empty)
        let graphs = try YAMLDecoder().decode(GraphsConfig.self, from: empty)
        let behavior = try YAMLDecoder().decode(BehaviorConfig.self, from: empty)
        let notifications = try YAMLDecoder().decode(NotificationsConfig.self, from: empty)

        let defBar = BarConfig()
        let defAppearance = AppearanceConfig()
        let defTypography = TypographyConfig()
        let defGraphs = GraphsConfig()
        let defBehavior = BehaviorConfig()
        let defNotifications = NotificationsConfig()

        #expect(bar.height == defBar.height)
        #expect(appearance.accent == defAppearance.accent)
        #expect(typography.iconFontSize == defTypography.iconFontSize)
        #expect(graphs.dataPoints == defGraphs.dataPoints)
        #expect(behavior.autoHide == defBehavior.autoHide)
        #expect(notifications.batteryLow == defNotifications.batteryLow)
    }
}
