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

    static let defaultThresholds: [ThresholdEntry] = [
        ThresholdEntry(above: 0.70, hex: 0xFF9F0A), // yellow
        ThresholdEntry(above: 0.90, hex: 0xFF3B30), // red
    ]

    var updateInterval: Double {
        didSet { notifyIfLive() }
    }

    var displayMode: GraphDisplayMode {
        didSet { notifyIfLive() }
    }

    var thresholds: [ThresholdEntry] {
        didSet { notifyIfLive() }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "memoryGraph")
        updateInterval = cfg?["updateInterval"]?.doubleValue ?? 2.0
        displayMode = cfg?["displayMode"]?.stringValue
            .flatMap(GraphDisplayMode.init(rawValue:)) ?? .graphOnly
        let decoded = cfg?["thresholds"]?.stringValue
            .map([ThresholdEntry].decoded(from:)) ?? []
        thresholds = decoded.isEmpty ? Self.defaultThresholds : decoded
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        [
            "updateInterval": .double(updateInterval),
            "displayMode": .string(displayMode.rawValue),
            "thresholds": .string(thresholds.encoded()),
        ]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["updateInterval"]?.doubleValue {
            updateInterval = v
        }
        if let v = values["displayMode"]?.stringValue {
            displayMode = GraphDisplayMode(rawValue: v) ?? displayMode
        }
        if let v = values["thresholds"]?.stringValue {
            let decoded = [ThresholdEntry].decoded(from: v)
            thresholds = decoded.isEmpty ? Self.defaultThresholds : decoded
        }
    }

    private func notifyIfLive() {
        if !suppressWrite {
            WidgetConfigRegistry.shared.notifySettingsChanged()
        }
    }
}

// MARK: - MemoryGraphWidget

@MainActor
@Observable
final class MemoryGraphWidget: StatusBarWidget, EventEmitting {
    let id = "memory-graph"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String {
        "memorychip"
    }

    private var timer: AnyCancellable?
    private let buffer = GraphDataBuffer(capacity: 50)
    private let service = SystemMonitorService.shared
    private var graphValues: [Double] = []

    func start() {
        restartTimer()
        observeTimerSettings()
        observeRenderSettings()
    }

    func stop() {
        timer?.cancel()
    }

    var hasSettings: Bool {
        true
    }

    var preferredSettingsSize: CGSize? {
        CGSize(width: 400, height: 400)
    }

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

    private func observeTimerSettings() {
        withObservationTracking {
            _ = MemoryGraphSettings.shared.updateInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.observeTimerSettings()
            }
        }
    }

    private func observeRenderSettings() {
        withObservationTracking {
            _ = MemoryGraphSettings.shared.displayMode
            _ = MemoryGraphSettings.shared.thresholds
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeRenderSettings()
            }
        }
    }

    private func update() {
        let usage = service.memoryUsage()
        buffer.push(usage)
        withAnimation(.numericTransition) {
            graphValues = buffer.values()
        }
        emitRaw(.memoryUpdated(percent: Int(usage * 100)))
    }

    private var latestUsagePercent: Int {
        Int((graphValues.last ?? 0) * 100)
    }

    func body() -> some View {
        let settings = MemoryGraphSettings.shared
        let activeColor = settings.thresholds.resolveColor(
            for: graphValues.last ?? 0,
            fallback: Theme.memoryGraph
        )

        HStack(spacing: 4) {
            if settings.displayMode != .numericOnly {
                MiniGraphView(
                    values: graphValues,
                    strokeColor: activeColor,
                    fillColor: activeColor.opacity(0.08)
                )
            }
            if settings.displayMode != .graphOnly {
                Text("\(latestUsagePercent)%")
                    .font(Theme.monoFont)
                    .foregroundStyle(activeColor)
                    .frame(minWidth: 32, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        }
        .onTapGesture {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory Usage")
        .accessibilityValue("\(latestUsagePercent)%")
    }
}
