import Foundation
@testable import StatusBar
import Testing
import Yams

struct MonitorConfigResolverTests {

    // MARK: - Resolution

    @Test("Empty rules falls back to global autoHide, no widget filter")
    func emptyRules() {
        let config = MonitorConfigResolver.resolve(
            screenName: "Built-in Retina Display",
            rules: [],
            globalAutoHide: true
        )
        #expect(config.autoHide == true)
        #expect(config.widgetFilter == nil)
    }

    @Test("Partial name match selects matching rule")
    func partialNameMatch() {
        let rules = [
            MonitorMatchRule(match: "Built-in", autoHide: true, widgets: ["time", "battery"]),
            MonitorMatchRule(match: "*", autoHide: false, widgets: nil),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "Built-in Retina Display",
            rules: rules,
            globalAutoHide: false
        )
        #expect(config.autoHide == true)
        #expect(config.widgetFilter == Set(["time", "battery"]))
    }

    @Test("Case-insensitive matching")
    func caseInsensitive() {
        let rules = [
            MonitorMatchRule(match: "lg ultrafine", autoHide: false, widgets: nil),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "LG UltraFine 5K",
            rules: rules,
            globalAutoHide: true
        )
        #expect(config.autoHide == false)
        #expect(config.widgetFilter == nil)
    }

    @Test("Wildcard matches any screen name")
    func wildcardMatch() {
        let rules = [
            MonitorMatchRule(match: "*", autoHide: true, widgets: ["cpu-graph"]),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "Some Unknown Monitor",
            rules: rules,
            globalAutoHide: false
        )
        #expect(config.autoHide == true)
        #expect(config.widgetFilter == Set(["cpu-graph"]))
    }

    @Test("First match wins when multiple rules match")
    func firstMatchWins() {
        let rules = [
            MonitorMatchRule(match: "Built-in", autoHide: true, widgets: ["time"]),
            MonitorMatchRule(match: "Built", autoHide: false, widgets: ["battery"]),
            MonitorMatchRule(match: "*", autoHide: false, widgets: nil),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "Built-in Retina Display",
            rules: rules,
            globalAutoHide: false
        )
        #expect(config.autoHide == true)
        #expect(config.widgetFilter == Set(["time"]))
    }

    @Test("No match and no wildcard falls back to global")
    func noMatchFallsBackToGlobal() {
        let rules = [
            MonitorMatchRule(match: "LG UltraFine", autoHide: true, widgets: ["time"]),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "Dell U2723QE",
            rules: rules,
            globalAutoHide: false
        )
        #expect(config.autoHide == false)
        #expect(config.widgetFilter == nil)
    }

    @Test("Rule with nil autoHide inherits global default")
    func nilAutoHideInheritsGlobal() {
        let rules = [
            MonitorMatchRule(match: "Built-in", autoHide: nil, widgets: ["time"]),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "Built-in Retina Display",
            rules: rules,
            globalAutoHide: true
        )
        #expect(config.autoHide == true)
        #expect(config.widgetFilter == Set(["time"]))
    }

    @Test("Empty widgets array produces empty filter set")
    func emptyWidgetsArray() {
        let rules = [
            MonitorMatchRule(match: "*", autoHide: false, widgets: []),
        ]
        let config = MonitorConfigResolver.resolve(
            screenName: "Any Monitor",
            rules: rules,
            globalAutoHide: false
        )
        #expect(config.widgetFilter == Set<String>())
    }

    // MARK: - YAML Round-Trip

    @Test("MonitorMatchRule round-trips through YAML")
    func monitorRuleRoundTrip() throws {
        let rule = MonitorMatchRule(match: "Built-in", autoHide: true, widgets: ["time", "battery"])
        let yaml = try YAMLEncoder().encode(rule)
        let decoded = try YAMLDecoder().decode(MonitorMatchRule.self, from: yaml)
        #expect(decoded == rule)
    }

    @Test("StatusBarConfig without monitors key decodes with empty array")
    func missingMonitorsKeyDecodesEmpty() throws {
        let yaml = """
        global:
          bar:
            height: 40
            cornerRadius: 12
            margin: 8
            yOffset: 4
            widgetSpacing: 6
            widgetPaddingH: 6
          appearance:
            accent: "#007AFF"
            textPrimaryOpacity: 1.0
            textSecondaryOpacity: 0.55
            textTertiaryOpacity: 0.3
            green: "#34C759"
            yellow: "#FF9F0A"
            red: "#FF3B30"
            cyan: "#64D2FF"
            purple: "#BF5AF2"
            barTint: "#000000"
            barTintOpacity: 0.0
            shadowEnabled: true
            popupCornerRadius: 10
            popupPadding: 12
          typography:
            iconFontSize: 13
            labelFontSize: 13
            smallFontSize: 11
            monoFontSize: 12
          graphs:
            width: 30
            height: 14
            dataPoints: 50
            cpuColor: "#007AFF"
            memoryColor: "#34C759"
          behavior:
            autoHide: false
            autoHideDwellTime: 0.3
            autoHideFadeDuration: 0.2
            launchAtLogin: false
            hideInFullscreen: true
          notifications:
            batteryLow: false
            batteryThreshold: 20.0
            cpuHigh: false
            cpuThreshold: 90.0
            cpuSustainedDuration: 5.0
            memoryHigh: false
            memoryThreshold: 90.0
            memorySustainedDuration: 5.0
        widgets: []
        widgetSettings: {}
        """
        let config = try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)
        #expect(config.monitors.isEmpty)
    }

    @Test("StatusBarConfig with monitors round-trips correctly")
    func monitorsRoundTrip() throws {
        var config = StatusBarConfig()
        config.monitors = [
            MonitorMatchRule(match: "Built-in", autoHide: true, widgets: ["time", "battery"]),
            MonitorMatchRule(match: "*", autoHide: false, widgets: nil),
        ]
        let yaml = try YAMLEncoder().encode(config)
        let decoded = try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)
        #expect(decoded.monitors.count == 2)
        #expect(decoded.monitors[0].match == "Built-in")
        #expect(decoded.monitors[0].autoHide == true)
        #expect(decoded.monitors[0].widgets == ["time", "battery"])
        #expect(decoded.monitors[1].match == "*")
        #expect(decoded.monitors[1].autoHide == false)
        #expect(decoded.monitors[1].widgets == nil)
    }
}
