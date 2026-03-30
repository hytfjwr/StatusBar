import AppKit
import StatusBarKit

@MainActor
final class BarWindowState {
    let window: BarWindow
    let screen: NSScreen
    var resolvedConfig: MonitorConfig
    var isHidden: Bool = false
    var dwellTimer: Timer?

    init(window: BarWindow, screen: NSScreen, resolvedConfig: MonitorConfig) {
        self.window = window
        self.screen = screen
        self.resolvedConfig = resolvedConfig
    }

    func invalidateDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }
}
