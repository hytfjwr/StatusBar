import Foundation
@testable import StatusBar
import StatusBarKit
import SwiftUI
import Testing

// MARK: - FakeLifecycleWidget

/// Minimal StatusBarWidget used to observe start()/stop() calls in lifecycle tests.
/// IDs use the `"test-fake-"` prefix so they don't collide with real widgets in the
/// shared WidgetRegistry singleton.
@MainActor
final class FakeLifecycleWidget: StatusBarWidget {
    let id: String
    let position: WidgetPosition
    let updateInterval: TimeInterval? = nil

    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(id: String, position: WidgetPosition = .left) {
        self.id = id
        self.position = position
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func body() -> some View {
        EmptyView()
    }
}

// MARK: - WidgetRegistryTests

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

    // MARK: - applyLayout lifecycle

    /// applyLayout should start widgets whose isVisible flipped false -> true so that
    /// hot-reload / preset switches correctly activate newly-visible widgets.
    @Test("applyLayout starts widgets that become visible")
    func applyLayoutStartsNewlyVisibleWidget() {
        let registry = WidgetRegistry.shared
        let widget = FakeLifecycleWidget(id: "test-fake-becomes-visible-\(UUID().uuidString)")
        registry.register(widget)
        defer { registry.unregisterWidgets(ids: [widget.id]) }

        // Baseline: widget hidden.
        registry.applyLayout([
            WidgetLayoutEntry(id: widget.id, section: .left, sortIndex: 0, isVisible: false),
        ])
        let startsBefore = widget.startCount
        let stopsBefore = widget.stopCount

        // Flip to visible.
        registry.applyLayout([
            WidgetLayoutEntry(id: widget.id, section: .left, sortIndex: 0, isVisible: true),
        ])

        #expect(widget.startCount == startsBefore + 1)
        #expect(widget.stopCount == stopsBefore)
    }

    /// applyLayout should stop widgets whose isVisible flipped true -> false so that
    /// timers / observers held by the widget are released on hot-reload.
    @Test("applyLayout stops widgets that become hidden")
    func applyLayoutStopsNewlyHiddenWidget() {
        let registry = WidgetRegistry.shared
        let widget = FakeLifecycleWidget(id: "test-fake-becomes-hidden-\(UUID().uuidString)")
        registry.register(widget)
        defer { registry.unregisterWidgets(ids: [widget.id]) }

        // Baseline: widget visible.
        registry.applyLayout([
            WidgetLayoutEntry(id: widget.id, section: .left, sortIndex: 0, isVisible: true),
        ])
        let startsBefore = widget.startCount
        let stopsBefore = widget.stopCount

        // Flip to hidden.
        registry.applyLayout([
            WidgetLayoutEntry(id: widget.id, section: .left, sortIndex: 0, isVisible: false),
        ])

        #expect(widget.stopCount == stopsBefore + 1)
        #expect(widget.startCount == startsBefore)
    }

    /// Re-applying an identical layout must be a no-op for lifecycle; otherwise the
    /// Mach / IOKit / NotificationCenter observers held by widgets double-register.
    @Test("applyLayout with no visibility change does not call start or stop")
    func applyLayoutNoChangeDoesNotToggle() {
        let registry = WidgetRegistry.shared
        let widget = FakeLifecycleWidget(id: "test-fake-stable-\(UUID().uuidString)")
        registry.register(widget)
        defer { registry.unregisterWidgets(ids: [widget.id]) }

        registry.applyLayout([
            WidgetLayoutEntry(id: widget.id, section: .left, sortIndex: 0, isVisible: true),
        ])
        let startsBefore = widget.startCount
        let stopsBefore = widget.stopCount

        // Apply the same visibility; section/sortIndex changes still count as "no visibility diff".
        registry.applyLayout([
            WidgetLayoutEntry(id: widget.id, section: .right, sortIndex: 5, isVisible: true),
        ])

        #expect(widget.startCount == startsBefore)
        #expect(widget.stopCount == stopsBefore)
    }
}
