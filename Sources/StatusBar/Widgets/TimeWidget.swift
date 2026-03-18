import Combine
import StatusBarKit
import SwiftUI

// MARK: - TimeSettings

@MainActor
@Observable
final class TimeSettings: WidgetConfigProvider {
    static let shared = TimeSettings()

    let configID = "time"
    private var suppressWrite = false

    var format: String {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "time")
        format = cfg?["format"]?.stringValue ?? "HH:mm"
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        ["format": .string(format)]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["format"]?.stringValue { format = v }
    }
}

// MARK: - TimeWidget

@MainActor
@Observable
final class TimeWidget: StatusBarWidget {
    let id = "time"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String { "clock" }

    private var currentTime = ""
    private var timer: AnyCancellable?
    private let formatter = DateFormatter()

    func start() {
        applyFormat()
        updateTime()
        timer = Timer.publish(every: 2, tolerance: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateTime() }
        observeSettings()
    }

    func stop() {
        timer?.cancel()
    }

    var hasSettings: Bool { true }

    func settingsBody() -> some View {
        TimeWidgetSettings()
    }

    private func applyFormat() {
        formatter.dateFormat = TimeSettings.shared.format
    }

    private func observeSettings() {
        withObservationTracking {
            _ = TimeSettings.shared.format
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFormat()
                self?.updateTime()
                self?.observeSettings()
            }
        }
    }

    private func updateTime() {
        currentTime = formatter.string(from: Date())
    }

    func body() -> some View {
        Text(currentTime)
            .font(Theme.labelFont)
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
    }
}
