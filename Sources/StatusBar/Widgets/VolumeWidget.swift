import StatusBarKit
import SwiftUI

// MARK: - VolumeWidget

@MainActor
@Observable
final class VolumeWidget: StatusBarWidget {
    let id = "volume"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String {
        "speaker.wave.2"
    }

    private var volume: Int = 0
    private var muted: Bool = false
    private var lastEmittedVolume: Int = -1
    private var lastEmittedMuted: Bool = false
    private var service: AudioService?
    private var popupPanel: PopupPanel?

    func start() {
        service = AudioService { [weak self] vol in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.volume = vol
                self.muted = self.service?.isMuted() ?? false
                if vol != self.lastEmittedVolume || self.muted != self.lastEmittedMuted {
                    self.lastEmittedVolume = vol
                    self.lastEmittedMuted = self.muted
                    EventBus.shared.emit(IPCEventEnvelope(
                        event: .volumeChanged,
                        payload: .volumeChanged(volume: vol, muted: self.muted)
                    ))
                }
                if self.popupPanel?.isVisible == true {
                    self.refreshPopup()
                }
            }
        }
        service?.start()
    }

    func stop() {
        service?.stop()
        popupPanel?.hidePopup()
    }

    private var iconName: String {
        if muted {
            return "speaker.slash.fill"
        }
        switch volume {
        case 60 ... 100: return "speaker.wave.3.fill"
        case 30 ..< 60: return "speaker.wave.2.fill"
        case 1 ..< 30: return "speaker.wave.1.fill"
        default: return "speaker.slash.fill"
        }
    }

    func body() -> some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(Theme.sfIconFont)
                .foregroundStyle(.primary)
                .frame(width: 18, alignment: .center)
            Text("\(volume)%")
                .font(Theme.labelFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .fixedSize()
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { [weak self] in
            self?.togglePopup()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume")
        .accessibilityValue(muted ? "Muted" : "\(volume)%")
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
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }

        let sliderVolume = muted ? service?.rawVolume() ?? volume : volume
        let content = VolumePopupContent(
            volume: sliderVolume,
            muted: muted,
            onVolumeChange: { [weak self] newVol in
                self?.service?.setVolume(newVol)
            },
            onMuteToggle: { [weak self] in
                guard let self else {
                    return
                }
                let newMute = !muted
                service?.setMute(newMute)
            }
        )
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }

    private func refreshPopup() {
        guard let panel = popupPanel, panel.isVisible else {
            return
        }

        let sliderVolume = muted ? service?.rawVolume() ?? volume : volume
        let content = VolumePopupContent(
            volume: sliderVolume,
            muted: muted,
            onVolumeChange: { [weak self] newVol in
                self?.service?.setVolume(newVol)
            },
            onMuteToggle: { [weak self] in
                guard let self else {
                    return
                }
                let newMute = !muted
                service?.setMute(newMute)
            }
        )
        panel.updateContent(content)
    }
}

// MARK: - VolumePopupContent

private struct VolumePopupContent: View {
    let volume: Int
    let muted: Bool
    let onVolumeChange: (Int) -> Void
    let onMuteToggle: () -> Void

    @State private var sliderValue: Double

    init(volume: Int, muted: Bool, onVolumeChange: @escaping (Int) -> Void, onMuteToggle: @escaping () -> Void) {
        self.volume = volume
        self.muted = muted
        self.onVolumeChange = onVolumeChange
        self.onMuteToggle = onMuteToggle
        _sliderValue = State(initialValue: Double(volume))
    }

    private var iconName: String {
        if muted {
            return "speaker.slash.fill"
        }
        switch Int(sliderValue) {
        case 60 ... 100: return "speaker.wave.3.fill"
        case 30 ..< 60: return "speaker.wave.2.fill"
        case 1 ..< 30: return "speaker.wave.1.fill"
        default: return "speaker.slash.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Volume")

            HStack(spacing: 10) {
                // Mute toggle button
                Button(action: onMuteToggle) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(muted ? .secondary : .primary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)

                // Horizontal slider
                Slider(value: $sliderValue, in: 0 ... 100, step: 1)
                    .tint(.blue)
                    .focusable(false)
                    .onChange(of: sliderValue) { _, newValue in
                        onVolumeChange(Int(newValue))
                    }

                // Percentage
                Text("\(Int(sliderValue))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(muted ? .secondary : .primary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .onChange(of: volume) { _, newValue in
            sliderValue = Double(newValue)
        }
    }
}
