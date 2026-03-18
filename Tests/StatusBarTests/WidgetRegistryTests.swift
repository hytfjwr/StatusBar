import Foundation
@testable import StatusBar
import Testing

@MainActor
struct WidgetRegistryTests {

    // MARK: - displayName

    @Test("Converts kebab-case to Title Case", arguments: [
        ("battery", "Battery"),
        ("focus-timer", "Focus Timer"),
        ("cpu-graph", "Cpu Graph"),
        ("mic-camera", "Mic Camera"),
        ("front-app", "Front App"),
        ("disk-usage", "Disk Usage"),
        ("input-source", "Input Source"),
    ])
    func displayName(widgetID: String, expected: String) {
        let result = WidgetRegistry.displayName(for: widgetID)
        #expect(result == expected)
    }

    @Test("Single word widget ID")
    func singleWordDisplayName() {
        #expect(WidgetRegistry.displayName(for: "volume") == "Volume")
        #expect(WidgetRegistry.displayName(for: "network") == "Network")
        #expect(WidgetRegistry.displayName(for: "time") == "Time")
    }

    @Test("Empty string returns empty")
    func emptyDisplayName() {
        #expect(WidgetRegistry.displayName(for: "") == "")
    }
}
