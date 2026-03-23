import Combine
import StatusBarKit
import SwiftUI

// MARK: - CPUGraphSettings

@MainActor
@Observable
final class CPUGraphSettings: WidgetConfigProvider {
    static let shared = CPUGraphSettings()

    let configID = "cpuGraph"
    private var suppressWrite = false

    static let defaultThresholds: [ThresholdEntry] = [
        ThresholdEntry(above: 0.60, hex: 0xFF9F0A), // yellow
        ThresholdEntry(above: 0.85, hex: 0xFF3B30), // red
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
        let cfg = WidgetConfigRegistry.shared.values(for: "cpuGraph")
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

// MARK: - CPUGraphWidget

@MainActor
@Observable
final class CPUGraphWidget: StatusBarWidget {
    let id = "cpu-graph"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String {
        "cpu"
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
        CPUGraphWidgetSettings()
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = CPUGraphSettings.shared.updateInterval
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    private func observeTimerSettings() {
        withObservationTracking {
            _ = CPUGraphSettings.shared.updateInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.observeTimerSettings()
            }
        }
    }

    private func observeRenderSettings() {
        withObservationTracking {
            _ = CPUGraphSettings.shared.displayMode
            _ = CPUGraphSettings.shared.thresholds
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeRenderSettings()
            }
        }
    }

    private func update() {
        let usage = service.cpuUsage()
        buffer.push(usage)
        graphValues = buffer.values()
    }

    private var latestUsagePercent: Int {
        Int((graphValues.last ?? 0) * 100)
    }

    func body() -> some View {
        let settings = CPUGraphSettings.shared
        let activeColor = settings.thresholds.resolveColor(
            for: graphValues.last ?? 0,
            fallback: Theme.cpuGraph
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
            }
        }
        .onTapGesture {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPU Usage")
        .accessibilityValue("\(latestUsagePercent)%")
    }
}

// MARK: - MiniGraphView

struct MiniGraphView: View {
    let values: [Double]
    let strokeColor: Color
    let fillColor: Color

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else {
                return
            }

            let stepX = size.width / CGFloat(max(values.count - 1, 1))
            var path = Path()

            for (i, value) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - CGFloat(value))
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Stroke
            context.stroke(path, with: .color(strokeColor), lineWidth: 1.2)

            // Fill
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(fillColor))
        }
        .frame(width: Theme.graphWidth, height: Theme.graphHeight)
    }
}
