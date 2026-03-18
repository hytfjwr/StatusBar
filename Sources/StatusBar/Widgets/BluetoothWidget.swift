import Combine
import StatusBarKit
import SwiftUI

// MARK: - BluetoothWidget

@MainActor
@Observable
final class BluetoothWidget: StatusBarWidget {
    let id = "bluetooth"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 10
    var sfSymbolName: String { "dot.radiowaves.right" }

    private var devices: [BluetoothService.BluetoothDevice] = []
    private var timer: AnyCancellable?
    private let service = BluetoothService()
    private var popupPanel: PopupPanel?

    private var connectedCount: Int { devices.count }

    func start() {
        devices = service.poll()
        let interval = updateInterval ?? 10
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.devices = self.service.poll()
                if self.popupPanel?.isVisible == true {
                    self.refreshPopup()
                }
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

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else { return }

        let content = BluetoothPopupContent(devices: devices)
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }

    private func refreshPopup() {
        guard let panel = popupPanel, panel.isVisible,
              let (barFrame, screen) = PopupPanel.barTriggerFrame()
        else { return }

        let content = BluetoothPopupContent(devices: devices)
        panel.showPopup(relativeTo: barFrame, on: screen, content: content)
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

                            if let battery = device.batteryLevel {
                                PopupStatusBadge(
                                    "\(battery)%",
                                    color: batteryColor(battery)
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 280)
    }

    private func batteryColor(_ level: Int) -> Color {
        if level > 50 { return Theme.green }
        if level > 20 { return Theme.yellow }
        return Theme.red
    }
}
