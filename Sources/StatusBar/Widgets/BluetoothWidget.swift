import Combine
import StatusBarKit
import SwiftUI

// MARK: - BluetoothEvent

enum BluetoothEvent {
    static let devicesChanged = "bluetooth_devices_changed"
    static let deviceConnected = "bluetooth_device_connected"
    static let deviceDisconnected = "bluetooth_device_disconnected"
    static let batteryLow = "bluetooth_battery_low"
}

extension IPCEventEnvelope {
    static func bluetoothDevicesChanged(devices: [BluetoothService.BluetoothDevice]) -> Self {
        IPCEventEnvelope(
            event: BluetoothEvent.devicesChanged,
            payload: .object([
                "connectedCount": .number(Double(devices.count)),
                "deviceNames": .array(devices.map { .string($0.name) }),
                "devices": .array(devices.map(deviceInfoPayload)),
            ])
        )
    }

    static func bluetoothDeviceConnected(name: String, category: String) -> Self {
        IPCEventEnvelope(
            event: BluetoothEvent.deviceConnected,
            payload: .object([
                "name": .string(name),
                "category": .string(category),
            ])
        )
    }

    static func bluetoothDeviceDisconnected(name: String) -> Self {
        IPCEventEnvelope(
            event: BluetoothEvent.deviceDisconnected,
            payload: .object(["name": .string(name)])
        )
    }

    static func bluetoothBatteryLow(deviceName: String, component: String?, percent: Int, threshold: Int) -> Self {
        var payload: [String: JSONValue] = [
            "deviceName": .string(deviceName),
            "percent": .number(Double(percent)),
            "threshold": .number(Double(threshold)),
        ]
        if let component {
            payload["component"] = .string(component)
        } else {
            payload["component"] = .null
        }
        return IPCEventEnvelope(event: BluetoothEvent.batteryLow, payload: .object(payload))
    }

    private static func deviceInfoPayload(_ device: BluetoothService.BluetoothDevice) -> JSONValue {
        var obj: [String: JSONValue] = [
            "name": .string(device.name),
            "category": .string(device.category.rawValue),
        ]
        if let b = device.batteryLevel {
            obj["battery"] = .number(Double(b))
        }
        if let l = device.leftBattery {
            obj["batteryLeft"] = .number(Double(l))
        }
        if let r = device.rightBattery {
            obj["batteryRight"] = .number(Double(r))
        }
        if let c = device.caseBattery {
            obj["batteryCase"] = .number(Double(c))
        }
        return .object(obj)
    }
}

// MARK: - BluetoothWidget

@MainActor
@Observable
final class BluetoothWidget: StatusBarWidget, EventEmitting {
    let id = "bluetooth"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 10
    var sfSymbolName: String {
        "dot.radiowaves.right"
    }

    private var devices: [BluetoothService.BluetoothDevice] = []
    private var timer: AnyCancellable?
    private let service = BluetoothService()
    private var popupPanel: PopupPanel?

    private var alertTracker = BluetoothBatteryAlertTracker()

    private var connectedCount: Int {
        devices.count
    }

    func start() {
        service.onAuthorized = { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        service.onBatteryCacheRefreshed = { [weak self] in
            self?.refresh()
        }
        refresh()
        let interval = updateInterval ?? 10
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func stop() {
        timer?.cancel()
        popupPanel?.hidePopup()
    }

    func body() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(Theme.sfIconFont)
                .foregroundStyle(.white)
            if connectedCount > 0 {
                Text("\(connectedCount)")
                    .font(Theme.labelFont)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { [weak self] in
            self?.togglePopup()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bluetooth")
        .accessibilityValue(connectedCount > 0 ? "\(connectedCount) devices connected" : "No devices")
    }

    func settingsBody() -> some View {
        BluetoothWidgetSettings()
    }

    // MARK: - Current devices (exposed for IPC runtime state)

    var currentDevices: [BluetoothService.BluetoothDevice] {
        devices
    }

    // MARK: - Refresh

    private func refresh() {
        let updated = service.poll()
        let dataChanged = updated != devices
        guard dataChanged else {
            fireBatteryAlerts(for: updated)
            return
        }

        let oldIDs = Set(devices.map(\.id))
        let newIDs = Set(updated.map(\.id))
        let topologyChanged = oldIDs != newIDs
        let added = updated.filter { !oldIDs.contains($0.id) }
        let removed = devices.filter { !newIDs.contains($0.id) }
        devices = updated

        // `bluetooth_devices_changed` is a topology-transition event — don't
        // fire it for battery-only fluctuations or the payload hits subscribers
        // every 10s while AirPods are in use. Battery changes are surfaced via
        // `bluetooth_battery_low` (threshold) instead.
        if topologyChanged {
            emit(.bluetoothDevicesChanged(devices: updated))
            for device in added {
                emit(.bluetoothDeviceConnected(
                    name: device.name,
                    category: device.category.rawValue
                ))
            }
            for device in removed {
                emit(.bluetoothDeviceDisconnected(name: device.name))
            }
        }
        fireBatteryAlerts(for: updated)
        if popupPanel?.isVisible == true {
            refreshPopup()
        }
    }

    // MARK: - Low-battery Detection

    /// Run the alert tracker against the latest readings and dispatch any
    /// transitions as toasts + IPC events. The tracker is pure; side effects
    /// live here so they stay injectable-free and isolated from the logic.
    private func fireBatteryAlerts(for devices: [BluetoothService.BluetoothDevice]) {
        let prefs = PreferencesModel.shared
        let threshold = Int(prefs.bluetoothBatteryThreshold)
        let alerts = alertTracker.evaluate(
            devices: devices,
            enabled: prefs.notifyBluetoothBatteryLow,
            threshold: threshold
        )
        for alert in alerts {
            let title = alert.component.map { "\(alert.deviceName) (\($0)) Low" } ?? "\(alert.deviceName) Low Battery"
            ToastManager.shared.post(ToastRequest(
                title: title,
                message: "Battery is at \(alert.percent)%",
                level: .warning
            ))
            emit(.bluetoothBatteryLow(
                deviceName: alert.deviceName,
                component: alert.component,
                percent: alert.percent,
                threshold: threshold
            ))
        }
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
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }

        let content = BluetoothPopupContent(devices: devices)
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }

    private func refreshPopup() {
        guard let panel = popupPanel, panel.isVisible else {
            return
        }
        // Update in place without re-reading the current mouse position —
        // the async `system_profiler` callback fires seconds after the user
        // clicked, so recomputing `barTriggerFrame()` here would snap the
        // popup to wherever the cursor has since moved.
        panel.updateContent(BluetoothPopupContent(devices: devices))
        panel.resizeToFitContent()
    }
}

// MARK: - BluetoothPopupContent

private struct BluetoothPopupContent: View {
    let devices: [BluetoothService.BluetoothDevice]

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Bluetooth")

            if devices.isEmpty {
                PopupEmptyState(icon: "bluetooth", message: "No devices connected")
            } else {
                VStack(spacing: 2) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 280)
    }

    private func deviceRow(_ device: BluetoothService.BluetoothDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.category.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accentBlue)
                .frame(width: 22, alignment: .center)
                .symbolRenderingMode(.hierarchical)

            Text(device.name)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if device.hasAirPodsDetail {
                airPodsBadges(device)
            } else if let battery = device.batteryLevel {
                PopupStatusBadge("\(battery)%", color: batteryColor(battery))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func airPodsBadges(_ device: BluetoothService.BluetoothDevice) -> some View {
        HStack(spacing: 4) {
            componentBadge(label: "L", value: device.leftBattery)
            componentBadge(label: "R", value: device.rightBattery)
            componentBadge(label: "C", value: device.caseBattery)
        }
    }

    @ViewBuilder
    private func componentBadge(label: String, value: Int?) -> some View {
        if let value {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                PopupStatusBadge("\(value)%", color: batteryColor(value))
            }
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        if level > 50 {
            return Theme.green
        }
        if level > 20 {
            return Theme.yellow
        }
        return Theme.red
    }
}
