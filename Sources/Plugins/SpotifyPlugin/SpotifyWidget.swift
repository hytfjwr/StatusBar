import StatusBarKit
import SwiftUI

// MARK: - SpotifyWidget

@MainActor
@Observable
public final class SpotifyWidget: StatusBarWidget {
    public let id = "spotify"
    public let position: WidgetPosition = .center
    public let updateInterval: TimeInterval? = nil
    public var sfSymbolName: String { "music.note" }

    private let service = SpotifyService()
    private var popupPanel: PopupPanel?

    public init() {}

    public func start() {
        service.start()
    }

    public func stop() {
        service.stop()
        popupPanel?.hidePopup()
    }

    @ViewBuilder
    public func body() -> some View {
        if service.isPlaying {
            HStack(spacing: 4) {
                AppIconView(appName: "Spotify", size: 18)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture { [weak self] in
                self?.togglePopup()
            }
        }
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
            let panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 340))
            panel.onHide = { [weak self] in
                self?.service.stopPositionPolling()
            }
            popupPanel = panel
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame(width: 100) else {
            return
        }

        service.fetchTrackInfo()
        service.startPositionPolling()

        let content = SpotifyPopupContent(service: service)
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }
}

// MARK: - SpotifyPopupContent

private struct SpotifyPopupContent: View {
    let service: SpotifyService

    private let artworkSize: CGFloat = 220
    private let popupWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // Album artwork — large, centered, with subtle shadow
            artworkView
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Track info — centered
            VStack(spacing: 4) {
                Text(service.trackName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(service.artistName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)

            // Seek bar (interactive)
            if service.duration > 0 {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { service.position },
                            set: { service.seekTo(position: $0) }
                        ),
                        in: 0...service.duration
                    )
                    .tint(.white)
                    .focusable(false)

                    HStack {
                        Text(formatTime(service.position))
                        Spacer()
                        Text(formatTime(service.duration))
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }

            // Playback controls — unified glass capsule
            HStack(spacing: 16) {
                toggleButton("shuffle", size: 14, isActive: service.isShuffling) { service.toggleShuffle() }
                controlButton("backward.fill", size: 18) { service.previousTrack() }
                // Play/Pause — prominent
                Button { service.playPause() } label: {
                    Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(ScalePressStyle())
                controlButton("forward.fill", size: 18) { service.nextTrack() }
                toggleButton("repeat", size: 14, isActive: service.isRepeating) { service.toggleRepeat() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .frame(width: popupWidth)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let url = service.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                artworkPlaceholder
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            )
    }

    private func controlButton(_ systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(ScalePressStyle())
    }

    private func toggleButton(_ systemName: String, size: CGFloat, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(isActive ? Color.green : .secondary)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay(alignment: .bottom) {
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                            .offset(y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(ScalePressStyle())
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - ScalePressStyle

private struct ScalePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}
