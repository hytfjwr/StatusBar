import Combine
import StatusBarKit
import SwiftUI

// MARK: - MemoryEvent

enum MemoryEvent {
    static let updated = "memory_updated"
    static let high = "memory_high"
}

extension IPCEventEnvelope {
    static func memoryUpdated(percent: Int) -> Self {
        IPCEventEnvelope(
            event: MemoryEvent.updated,
            payload: .object(["percent": .number(Double(percent))])
        )
    }

    static func memoryHigh(usagePercent: Int, threshold: Int, sustainedSeconds: Int) -> Self {
        IPCEventEnvelope(
            event: MemoryEvent.high,
            payload: .object([
                "usagePercent": .number(Double(usagePercent)),
                "threshold": .number(Double(threshold)),
                "sustainedSeconds": .number(Double(sustainedSeconds)),
            ])
        )
    }
}

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
    private var isRunning = false

    private var popupPanel: PopupPanel?
    private var popupSnapshot: SystemMonitorService.MemorySnapshot?
    private var popupProcesses: [ProcessInfoService.ProcessSample] = []
    private var processFetchInFlight = false
    private var processFetchCompleted = false

    func start() {
        isRunning = true
        restartTimer()
        observeTimerSettings()
        observeRenderSettings()
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        popupPanel?.hidePopup()
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
                guard let self, self.isRunning else {
                    return
                }
                self.restartTimer()
                self.observeTimerSettings()
            }
        }
    }

    private func observeRenderSettings() {
        withObservationTracking {
            _ = MemoryGraphSettings.shared.displayMode
            _ = MemoryGraphSettings.shared.thresholds
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning else {
                    return
                }
                self.observeRenderSettings()
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
        if popupPanel?.isVisible == true {
            refreshPopupData()
        }
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
        .onTapGesture { [weak self] in
            self?.togglePopup()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory Usage")
        .accessibilityValue("\(latestUsagePercent)%")
    }

    // MARK: - Popup

    private func togglePopup() {
        if popupPanel?.isVisible == true {
            popupPanel?.hidePopup()
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        if popupPanel == nil {
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }

        refreshPopupData()
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: makePopupContent())
    }

    private func refreshPopupData() {
        popupSnapshot = service.memorySnapshot()
        refreshPopup()

        guard !processFetchInFlight else {
            return
        }
        processFetchInFlight = true
        Task { [weak self] in
            let samples = await ProcessInfoService.sample(sortedBy: .memory)
            guard let self else {
                return
            }
            processFetchInFlight = false
            processFetchCompleted = true
            popupProcesses = ProcessInfoService.topByMemory(samples)
            refreshPopup()
        }
    }

    private func refreshPopup() {
        guard let panel = popupPanel, panel.isVisible else {
            return
        }
        panel.updateContent(makePopupContent())
        panel.resizeToFitContent()
    }

    private func makePopupContent() -> MemoryPopupContent {
        MemoryPopupContent(
            snapshot: popupSnapshot,
            processes: popupProcesses,
            processesLoaded: processFetchCompleted,
            onOpenActivityMonitor: { [weak self] in
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                )
                self?.popupPanel?.hidePopup()
            }
        )
    }
}

// MARK: - MemoryPopupContent

private struct MemoryPopupContent: View {
    let snapshot: SystemMonitorService.MemorySnapshot?
    let processes: [ProcessInfoService.ProcessSample]
    let processesLoaded: Bool
    let onOpenActivityMonitor: () -> Void

    private func usageColor(_ fraction: Double) -> Color {
        if fraction >= 0.85 {
            return Theme.red
        }
        if fraction >= 0.60 {
            return Theme.yellow
        }
        return Theme.green
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Memory")

            if let snapshot {
                VStack(spacing: 6) {
                    UsageBarRow(
                        label: "Used",
                        fraction: snapshot.usedFraction,
                        color: usageColor(snapshot.usedFraction),
                        valueText: "\(formatBytes(snapshot.usedBytes)) / \(formatBytes(snapshot.totalBytes))"
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

                VStack(spacing: 2) {
                    PopupInfoRow(icon: "app.badge", label: "App Memory", value: formatBytes(snapshot.appBytes))
                    PopupInfoRow(icon: "pin.fill", label: "Wired", value: formatBytes(snapshot.wiredBytes))
                    PopupInfoRow(
                        icon: "arrow.down.right.and.arrow.up.left",
                        label: "Compressed",
                        value: formatBytes(snapshot.compressedBytes)
                    )
                    if snapshot.swapTotalBytes > 0 {
                        PopupInfoRow(
                            icon: "arrow.left.arrow.right",
                            label: "Swap",
                            value: "\(formatBytes(snapshot.swapUsedBytes)) / \(formatBytes(snapshot.swapTotalBytes))"
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }

            PopupDivider()
            PopupSectionHeader("Top Processes")

            if processes.isEmpty {
                PopupEmptyState(icon: "memorychip", message: processesLoaded ? "Unavailable" : "Loading…")
            } else {
                VStack(spacing: 2) {
                    ForEach(processes) { process in
                        ProcessRow(
                            name: process.name,
                            valueText: formatBytes(process.residentBytes),
                            valueColor: Theme.accentBlue
                        )
                    }
                }
                .padding(.horizontal, 6)
            }

            PopupDivider()
            PopupRow(icon: "chart.bar.xaxis", label: "Open Activity Monitor") {
                onOpenActivityMonitor()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 300)
    }
}
