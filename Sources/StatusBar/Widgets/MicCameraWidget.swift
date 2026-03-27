import StatusBarKit
import SwiftUI

// MARK: - MicCameraEvent

enum MicCameraEvent {
    static let changed = "mic_camera_changed"
    static let micActivated = "mic_activated"
    static let micDeactivated = "mic_deactivated"
    static let cameraActivated = "camera_activated"
    static let cameraDeactivated = "camera_deactivated"
}

extension IPCEventEnvelope {
    static func micCameraChanged(micActive: Bool, cameraActive: Bool) -> Self {
        IPCEventEnvelope(
            event: MicCameraEvent.changed,
            payload: .object([
                "micActive": .bool(micActive),
                "cameraActive": .bool(cameraActive),
            ])
        )
    }

    static func micActivated() -> Self {
        IPCEventEnvelope(event: MicCameraEvent.micActivated)
    }

    static func micDeactivated() -> Self {
        IPCEventEnvelope(event: MicCameraEvent.micDeactivated)
    }

    static func cameraActivated() -> Self {
        IPCEventEnvelope(event: MicCameraEvent.cameraActivated)
    }

    static func cameraDeactivated() -> Self {
        IPCEventEnvelope(event: MicCameraEvent.cameraDeactivated)
    }
}

// MARK: - MicCameraWidget

@MainActor
@Observable
final class MicCameraWidget: StatusBarWidget, EventEmitting {
    let id = "mic-camera"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String {
        "video"
    }

    private var micActive = false
    private var cameraActive = false
    private var service: MicCameraService?

    func start() {
        service = MicCameraService { [weak self] state in
            Task { @MainActor in
                guard let self else {
                    return
                }
                let wasMic = self.micActive
                let wasCamera = self.cameraActive
                self.micActive = state.micActive
                self.cameraActive = state.cameraActive
                self.emit(.micCameraChanged(micActive: state.micActive, cameraActive: state.cameraActive))
                if state.micActive != wasMic {
                    self.emit(state.micActive ? .micActivated() : .micDeactivated())
                }
                if state.cameraActive != wasCamera {
                    self.emit(state.cameraActive ? .cameraActivated() : .cameraDeactivated())
                }
            }
        }
        service?.start()
    }

    func stop() {
        service?.stop()
        service = nil
    }

    private var accessibilityStateDescription: String {
        switch (micActive, cameraActive) {
        case (true, true): "Microphone and camera active"
        case (true, false): "Microphone active"
        case (false, true): "Camera active"
        case (false, false): ""
        }
    }

    @ViewBuilder
    func body() -> some View {
        if micActive || cameraActive {
            HStack(spacing: 4) {
                if micActive {
                    Image(systemName: "mic.fill")
                        .font(Theme.sfIconFont)
                        .foregroundStyle(Theme.red)
                }
                if cameraActive {
                    Image(systemName: "video.fill")
                        .font(Theme.sfIconFont)
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: .rect(cornerRadius: 4))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Microphone and Camera")
            .accessibilityValue(accessibilityStateDescription)
        }
    }
}
