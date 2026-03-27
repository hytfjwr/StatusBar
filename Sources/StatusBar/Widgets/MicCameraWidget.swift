import StatusBarKit
import SwiftUI

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
    private var lastEmittedMic = false
    private var lastEmittedCamera = false
    private var service: MicCameraService?

    func start() {
        service = MicCameraService { [weak self] state in
            Task { @MainActor in
                guard let self else {
                    return
                }
                let wasMic = self.lastEmittedMic
                let wasCamera = self.lastEmittedCamera
                self.micActive = state.micActive
                self.cameraActive = state.cameraActive
                self.emit(.micCameraChanged(micActive: state.micActive, cameraActive: state.cameraActive))
                if state.micActive != wasMic {
                    self.lastEmittedMic = state.micActive
                    self.emit(state.micActive ? .micActivated() : .micDeactivated())
                }
                if state.cameraActive != wasCamera {
                    self.lastEmittedCamera = state.cameraActive
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
