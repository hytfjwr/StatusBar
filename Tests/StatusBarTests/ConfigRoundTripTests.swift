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
}
