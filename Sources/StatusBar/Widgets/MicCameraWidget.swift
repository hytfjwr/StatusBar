import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class MicCameraWidget: StatusBarWidget {
    let id = "mic-camera"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String { "video" }

    private var micActive = false
    private var service: MicCameraService?

    func start() {
        service = MicCameraService { [weak self] state in
            Task { @MainActor in
                self?.micActive = state.micActive
            }
        }
        service?.start()
    }

    func stop() {
        service?.stop()
        service = nil
    }

    @ViewBuilder
    func body() -> some View {
        if micActive {
            Image(systemName: "mic.fill")
                .font(Theme.sfIconFont)
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: .rect(cornerRadius: 4))
        }
    }
}
