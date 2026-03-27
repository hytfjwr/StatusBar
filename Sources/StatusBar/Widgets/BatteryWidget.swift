import Combine
import StatusBarKit
import SwiftUI

// MARK: - BatteryEvent

enum BatteryEvent {
    static let changed = "battery_changed"
    static let chargingChanged = "battery_charging_changed"
    static let low = "battery_low"
}

extension IPCEventEnvelope {
    static func batteryChanged(percent: Int, charging: Bool, hasBattery: Bool) -> Self {
        IPCEventEnvelope(
            event: BatteryEvent.changed,
            payload: .object([
                "percent": .number(Double(percent)),
                "charging": .bool(charging),
                "hasBattery": .bool(hasBattery),
            ])
        )
    }

    static func batteryChargingChanged(charging: Bool) -> Self {
        IPCEventEnvelope(
            event: BatteryEvent.chargingChanged,
            payload: .object(["charging": .bool(charging)])
        )
    }

    static func batteryLow(percent: Int, threshold: Int) -> Self {
        IPCEventEnvelope(
            event: BatteryEvent.low,
            payload: .object([
                "percent": .number(Double(percent)),
                "threshold": .number(Double(threshold)),
            ])
        )
    }
}

// MARK: - BatterySettings

@MainActor
@Observable
final class BatterySettings: WidgetConfigProvider {
    static let shared = BatterySettings()

    let configID = "battery"
    private var suppressWrite = false

    var showPercentage: Bool {
        didSet { if !suppressWrite {
            WidgetConfigRegistry.shared.notifySettingsChanged()
        } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "battery")
        showPercentage = cfg?["showPercentage"]?.boolValue ?? true
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        ["showPercentage": .bool(showPercentage)]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["showPercentage"]?.boolValue {
            showPercentage = v
        }
    }
}

// MARK: - BatteryWidget

@MainActor
@Observable
final class BatteryWidget: StatusBarWidget, EventEmitting {
    let id = "battery"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 120
    var sfSymbolName: String {
        "battery.75percent"
    }

    private var percentage: Int = 0
    private var isCharging = false
    private var hasBattery = true
    private var showPercentage = true
    func start() {
        showPercentage = BatterySettings.shared.showPercentage
        BatteryService.shared.addObserver { [weak self] pct, charging, battery in
            guard let self else {
                return
            }
            let wasCharging = isCharging
            withAnimation(.numericTransition) {
                self.percentage = pct
                self.isCharging = charging
                self.hasBattery = battery
            }
            emitRaw(.batteryChanged(percent: pct, charging: charging, hasBattery: battery))
            if charging != wasCharging {
                emit(.batteryChargingChanged(charging: charging))
            }
        }
        BatteryService.shared.start()
        observeSettings()
    }

    func stop() {
        // Singleton is shared; stop is managed centrally
    }

    var hasSettings: Bool {
        true
    }

    func settingsBody() -> some View {
        BatteryWidgetSettings()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = BatterySettings.shared.showPercentage
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.showPercentage = BatterySettings.shared.showPercentage
                self?.observeSettings()
            }
        }
    }

    private var iconName: String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch percentage {
        case 80 ... 100: return "battery.100"
        case 50 ..< 80: return "battery.75"
        case 20 ..< 50: return "battery.50"
        case 5 ..< 20: return "battery.25"
        default: return "battery.0"
        }
    }

    private var iconStyle: AnyShapeStyle {
        if isCharging {
            return AnyShapeStyle(Theme.green)
        }
        if percentage <= 10 {
            return AnyShapeStyle(Theme.red)
        }
        if percentage <= 20 {
            return AnyShapeStyle(Theme.yellow)
        }
        return AnyShapeStyle(.primary)
    }

    @ViewBuilder
    func body() -> some View {
        if hasBattery {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(Theme.sfIconFont)
                    .foregroundStyle(iconStyle)
                if showPercentage {
                    Text("\(percentage)%")
                        .font(Theme.labelFont)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery")
            .accessibilityValue(isCharging ? "Charging \(percentage)%" : "\(percentage)%")
        }
    }
}
