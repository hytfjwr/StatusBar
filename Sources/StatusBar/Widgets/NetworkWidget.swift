import Combine
import StatusBarKit
import SwiftUI

// MARK: - NetworkSettings

@MainActor
@Observable
final class NetworkSettings: WidgetConfigProvider {
    static let shared = NetworkSettings()

    let configID = "network"
    private var suppressWrite = false

    var updateInterval: Double {
        didSet { if !suppressWrite {
            WidgetConfigRegistry.shared.notifySettingsChanged()
        } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "network")
        updateInterval = cfg?["updateInterval"]?.doubleValue ?? 2.0
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        ["updateInterval": .double(updateInterval)]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["updateInterval"]?.doubleValue {
            updateInterval = v
        }
    }
}

// MARK: - NetworkWidget

@MainActor
@Observable
final class NetworkWidget: StatusBarWidget {
    let id = "network"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String {
        "network"
    }

    private var timer: AnyCancellable?
    private let service = NetworkService()
    private var uploadSpeed = "0 kB/s"
    private var downloadSpeed = "0 kB/s"

    func start() {
        restartTimer()
        observeSettings()
    }

    func stop() {
        timer?.cancel()
    }

    var hasSettings: Bool {
        true
    }

    func settingsBody() -> some View {
        NetworkWidgetSettings()
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = NetworkSettings.shared.updateInterval
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = NetworkSettings.shared.updateInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.observeSettings()
            }
        }
    }

    private func update() {
        let speed = service.poll()
        withAnimation(.numericTransition) {
            uploadSpeed = speed.uploadFormatted
            downloadSpeed = speed.downloadFormatted
        }
    }

    func body() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(Theme.smallFont)
                    .foregroundStyle(.tertiary)
                Text(uploadSpeed)
                    .font(Theme.smallFont)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(Theme.smallFont)
                    .foregroundStyle(.tertiary)
                Text(downloadSpeed)
                    .font(Theme.smallFont)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Network")
        .accessibilityValue("Upload \(uploadSpeed) Download \(downloadSpeed)")
    }
}
