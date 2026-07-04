import Combine
import StatusBarKit
import SwiftUI

// MARK: - NetworkEvent

enum NetworkEvent {
    static let updated = "network_updated"
}

extension IPCEventEnvelope {
    static func networkUpdated(downloadBytesPerSec: Double, uploadBytesPerSec: Double) -> Self {
        IPCEventEnvelope(
            event: NetworkEvent.updated,
            payload: .object([
                "downloadBytesPerSec": .number(downloadBytesPerSec),
                "uploadBytesPerSec": .number(uploadBytesPerSec),
            ])
        )
    }
}

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
final class NetworkWidget: StatusBarWidget, EventEmitting {
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
    private var isRunning = false

    private var popupPanel: PopupPanel?
    private var latestSnapshot: NetworkService.NetworkSnapshot?
    private var publicIP: String?
    private var popupLoadingPublicIP = false

    func start() {
        isRunning = true
        restartTimer()
        observeSettings()
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        popupPanel?.hidePopup()
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
                guard let self, self.isRunning else {
                    return
                }
                self.restartTimer()
                self.observeSettings()
            }
        }
    }

    private func update() {
        let speed = service.poll()
        latestSnapshot = speed
        withAnimation(.numericTransition) {
            uploadSpeed = speed.uploadFormatted
            downloadSpeed = speed.downloadFormatted
        }
        emitRaw(.networkUpdated(downloadBytesPerSec: speed.download, uploadBytesPerSec: speed.upload))
        if popupPanel?.isVisible == true {
            refreshPopup()
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
        .contentShape(Rectangle())
        .onTapGesture { [weak self] in
            self?.togglePopup()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Network")
        .accessibilityValue("Upload \(uploadSpeed) Download \(downloadSpeed)")
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

        popupLoadingPublicIP = true
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: makePopupContent())

        Task { [weak self] in
            guard let self else {
                return
            }
            let ip = await PublicIPService.shared.fetch()
            popupLoadingPublicIP = false
            publicIP = ip
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

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ToastManager.shared.post(ToastRequest(title: "Copied", message: text, level: .info))
    }

    private func makePopupContent() -> NetworkPopupContent {
        NetworkPopupContent(
            snapshot: latestSnapshot,
            publicIP: publicIP,
            loadingPublicIP: popupLoadingPublicIP,
            onCopy: { [weak self] text in
                self?.copyToPasteboard(text)
            },
            onOpenNetworkSettings: { [weak self] in
                if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
                self?.popupPanel?.hidePopup()
            }
        )
    }
}

// MARK: - NetworkPopupContent

private struct NetworkPopupContent: View {
    let snapshot: NetworkService.NetworkSnapshot?
    let publicIP: String?
    let loadingPublicIP: Bool
    let onCopy: (String) -> Void
    let onOpenNetworkSettings: () -> Void

    private var ssid: String? {
        WiFiService.currentSSID()
    }

    private var localAddresses: [(name: String, address: String)] {
        Array(NetworkService.localIPv4Addresses().prefix(2))
    }

    private var publicIPText: String {
        if let publicIP {
            return publicIP
        }
        return loadingPublicIP ? "…" : "Unavailable"
    }

    private var topInterfaces: [NetworkService.InterfaceSpeed] {
        (snapshot?.interfaces ?? [])
            .filter { $0.download > 0 || $0.upload > 0 }
            .sorted { $0.download + $0.upload > $1.download + $1.upload }
            .prefix(4)
            .map(\.self)
    }

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Network")

            VStack(spacing: 2) {
                if let ssid {
                    PopupInfoRow(icon: "wifi", label: "Wi-Fi", value: ssid)
                }
                ForEach(localAddresses, id: \.name) { entry in
                    PopupInfoRow(icon: "network", label: entry.name, value: entry.address) {
                        onCopy(entry.address)
                    }
                }
                PopupInfoRow(icon: "globe", label: "Public IP", value: publicIPText) {
                    if let publicIP {
                        onCopy(publicIP)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            if !topInterfaces.isEmpty {
                PopupDivider()
                PopupSectionHeader("Interfaces")

                VStack(spacing: 2) {
                    ForEach(topInterfaces, id: \.name) { iface in
                        PopupInfoRow(
                            icon: "arrow.up.arrow.down",
                            label: iface.name,
                            value: "↓ \(NetworkService.NetworkSnapshot.formatSpeed(iface.download))" +
                                "  ↑ \(NetworkService.NetworkSnapshot.formatSpeed(iface.upload))"
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }

            PopupDivider()
            PopupRow(icon: "gearshape", label: "Open Network Settings") {
                onOpenNetworkSettings()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 300)
    }
}
