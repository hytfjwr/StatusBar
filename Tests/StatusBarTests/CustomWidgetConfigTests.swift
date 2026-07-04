import Foundation
@testable import StatusBar
import StatusBarKit
import Testing
import Yams

// MARK: - CustomWidgetConfigTests

struct CustomWidgetConfigTests {
    @Test("All fields decode correctly from YAML")
    func fullEntryDecodes() throws {
        let yaml = """
        id: k8s-context
        position: right
        icon: "⎈"
        script: "kubectl config current-context"
        interval: 30
        clickScript: "open -a Lens"
        timeout: 10
        """

        let decoded = try YAMLDecoder().decode(CustomWidgetConfig.self, from: yaml)

        #expect(decoded.id == "k8s-context")
        #expect(decoded.position == .right)
        #expect(decoded.icon == "⎈")
        #expect(decoded.script == "kubectl config current-context")
        #expect(decoded.interval == 30)
        #expect(decoded.clickScript == "open -a Lens")
        #expect(decoded.timeout == 10)
    }

    @Test("Minimal entry (id + script only) falls back to defaults")
    func minimalEntryUsesDefaults() throws {
        let yaml = """
        id: my-widget
        script: "echo hi"
        """

        let decoded = try YAMLDecoder().decode(CustomWidgetConfig.self, from: yaml)

        #expect(decoded.id == "my-widget")
        #expect(decoded.script == "echo hi")
        #expect(decoded.position == .right)
        #expect(decoded.interval == 30)
        #expect(decoded.timeout == 5)
        #expect(decoded.icon == nil)
        #expect(decoded.sfSymbol == nil)
        #expect(decoded.clickScript == nil)
    }

    @Test("Invalid position string falls back to .right without throwing")
    func invalidPositionFallsBack() throws {
        let yaml = """
        id: my-widget
        script: "echo hi"
        position: top
        """

        let decoded = try YAMLDecoder().decode(CustomWidgetConfig.self, from: yaml)
        #expect(decoded.position == .right)
    }

    @Test("interval: 0 disables the timer")
    func zeroIntervalDisablesTimer() {
        var config = CustomWidgetConfig(id: "x", script: "echo hi", interval: 0)
        #expect(config.timerInterval == nil)

        config.interval = -5
        #expect(config.timerInterval == nil)
    }

    @Test("Sub-1-second interval is clamped to 1 second")
    func fractionalIntervalClampedToOneSecond() {
        let config = CustomWidgetConfig(id: "x", script: "echo hi", interval: 0.5)
        #expect(config.timerInterval == 1)
    }

    @Test("timeout is clamped to [1, 30]")
    func timeoutClamped() {
        let tooHigh = CustomWidgetConfig(id: "x", script: "echo hi", timeout: 99)
        #expect(tooHigh.clampedTimeout == 30)

        let tooLow = CustomWidgetConfig(id: "x", script: "echo hi", timeout: 0)
        #expect(tooLow.clampedTimeout == 1)
    }

    @Test("widgetID is prefixed with 'custom-'")
    func widgetIDHasPrefix() {
        let config = CustomWidgetConfig(id: "k8s-context", script: "echo hi")
        #expect(config.widgetID == "custom-k8s-context")
    }

    @Test("StatusBarConfig without a customWidgets key decodes to an empty array")
    func missingCustomWidgetsKeyDecodesEmpty() throws {
        let yaml = """
        widgets: []
        widgetSettings: {}
        """
        let decoded = try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)
        #expect(decoded.customWidgets.isEmpty)
    }

    @Test("StatusBarConfig customWidgets survive an encode/decode round trip")
    func customWidgetsRoundTrip() throws {
        var config = StatusBarConfig()
        config.customWidgets = [
            CustomWidgetConfig(
                id: "k8s-context",
                script: "kubectl config current-context",
                position: .left,
                icon: "⎈",
                sfSymbol: nil,
                interval: 15,
                clickScript: "open -a Lens",
                timeout: 8
            ),
        ]

        let yaml = try YAMLEncoder().encode(config)
        let decoded = try YAMLDecoder().decode(StatusBarConfig.self, from: yaml)

        #expect(decoded.customWidgets == config.customWidgets)
    }
}
