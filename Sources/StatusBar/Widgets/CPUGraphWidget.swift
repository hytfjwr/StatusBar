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

    var updateInterval: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "cpuGraph")
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

// MARK: - CPUGraphWidget

@MainActor
@Observable
final class CPUGraphWidget: StatusBarWidget {
    let id = "cpu-graph"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String { "cpu" }

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
        CPUGraphWidgetSettings()
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = CPUGraphSettings.shared.updateInterval
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = CPUGraphSettings.shared.updateInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.observeSettings()
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
        MiniGraphView(
            values: graphValues,
            strokeColor: Theme.cpuGraph,
            fillColor: Theme.cpuGraph.opacity(0.08)
        )
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
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
