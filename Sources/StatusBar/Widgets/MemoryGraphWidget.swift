import Combine
import StatusBarKit
import SwiftUI

// MARK: - MemoryGraphSettings

@MainActor
@Observable
final class MemoryGraphSettings: WidgetConfigProvider {
    static let shared = MemoryGraphSettings()

    let configID = "memoryGraph"
    private var suppressWrite = false

    var updateInterval: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "memoryGraph")
        updateInterval = cfg?["updateInterval"]?.doubleValue ?? 2.0
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        ["updateInterval": .double(updateInterval)]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["updateInterval"]?.doubleValue { updateInterval = v }
    }
}

// MARK: - MemoryGraphWidget

@MainActor
@Observable
final class MemoryGraphWidget: StatusBarWidget {
    let id = "memory-graph"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String { "memorychip" }

    private var timer: AnyCancellable?
    private let buffer = GraphDataBuffer(capacity: 50)
    private let service = SystemMonitorService.shared
    private var graphValues: [Double] = []

    func start() {
        restartTimer()
        observeSettings()
    }

    func stop() {
        timer?.cancel()
    }

    var hasSettings: Bool { true }

    func settingsBody() -> some View {
        MemoryGraphWidgetSettings()
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = MemoryGraphSettings.shared.updateInterval
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = MemoryGraphSettings.shared.updateInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.observeSettings()
            }
        }
    }

    private func update() {
        let usage = service.memoryUsage()
        buffer.push(usage)
        graphValues = buffer.values()
    }

    private var latestUsagePercent: Int {
        Int((graphValues.last ?? 0) * 100)
    }

    func body() -> some View {
        MiniGraphView(
            values: graphValues,
            strokeColor: Theme.memoryGraph,
            fillColor: Theme.memoryGraph.opacity(0.08)
        )
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory Usage")
        .accessibilityValue("\(latestUsagePercent)%")
    }
}
