import AppKit
import StatusBarKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var barWindows: [BarWindow] = []
    private let registry = WidgetRegistry.shared
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var dwellTimer: Timer?
    private var isBarHidden = false
    private var rebuildTask: Task<Void, Never>?
    private var spaceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var fullscreenHiddenIndices: Set<Int> = []

    func setup() {
        createBarWindows()
        registry.startAll()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }

        observeBarDimensions()
        observeShadowPreferences()
        observeTintPreferences()
        observeBehaviorPreferences()
        observeFullscreenPreference()
    }

    private func createBarWindows() {
        barWindows.forEach { $0.orderOut(nil) }
        barWindows.removeAll()
        fullscreenHiddenIndices.removeAll()

        for (index, screen) in NSScreen.screens.enumerated() {
            let window = BarWindow(screen: screen)
            let contentView = BarContentView(registry: registry, screenIndex: index)
            window.setContent(contentView)
            window.orderFrontRegardless()
            barWindows.append(window)
        }

        updateFullscreenVisibility()
        setupToastManager()
    }

    private func handleScreenChange() {
        createBarWindows()
    }

    private func setupToastManager() {
        guard let primaryWindow = barWindows.first, let screen = NSScreen.screens.first else {
            return
        }
        ToastManager.shared.reposition(anchoredTo: primaryWindow, on: screen)
    }

    /// Observe bar dimension preferences and rebuild windows when they change.
    /// Debounced to avoid per-frame window recreation during slider drag.
    private func observeBarDimensions() {
        withObservationTracking {
            let prefs = PreferencesModel.shared
            _ = prefs.barHeight
            _ = prefs.barMargin
            _ = prefs.barYOffset
            _ = prefs.barCornerRadius
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildTask?.cancel()
                self?.rebuildTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.createBarWindows()
                }
                self?.observeBarDimensions()
            }
        }
    }

    /// Observe shadow preferences and re-apply shadow when they change.
    private func observeShadowPreferences() {
        withObservationTracking {
            _ = PreferencesModel.shared.shadowEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.barWindows.forEach { GlassEffect.applyShadow(to: $0) }
                self?.observeShadowPreferences()
            }
        }
    }

    /// Observe glass tint preferences and re-apply tint when they change.
    private func observeTintPreferences() {
        withObservationTracking {
            let prefs = PreferencesModel.shared
            _ = prefs.barTintOpacity
            _ = prefs.barTintHex
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.barWindows.forEach { $0.updateTint() }
                PopupManager.shared.updateTint()
                ToastManager.shared.updateTint()
                self?.observeTintPreferences()
            }
        }
    }

    // MARK: - Behavior Preferences

    private func observeBehaviorPreferences() {
        withObservationTracking {
            _ = PreferencesModel.shared.autoHideEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyAutoHideState()
                self?.observeBehaviorPreferences()
            }
        }
        applyAutoHideState()
    }

    private func applyAutoHideState() {
        let enabled = PreferencesModel.shared.autoHideEnabled
        if enabled, mouseMonitor == nil {
            installMouseMonitor()
        } else if !enabled {
            removeMouseMonitor()
            // Restore bar if it was hidden
            if isBarHidden {
                isBarHidden = false
                fadeBarWindows(hide: false)
            }
        }
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseMove()
            }
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    // MARK: - Menu Bar Auto-Hide Detection

    private func handleMouseMove() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation)
        }) else {
            return
        }
        let mouseY = mouseLocation.y
        let screenTop = screen.frame.maxY
        let distanceFromTop = screenTop - mouseY

        if distanceFromTop <= 2 {
            // Cursor at the very top edge — start dwell timer to hide
            if !isBarHidden, dwellTimer == nil {
                let dwellTime = PreferencesModel.shared.autoHideDwellTime
                dwellTimer = Timer.scheduledTimer(withTimeInterval: dwellTime, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.isBarHidden = true
                        self?.fadeBarWindows(hide: true)
                    }
                }
            }
        } else {
            let barBottom = screenTop - Theme.barHeight - Theme.barYOffset
            if isBarHidden, mouseY < barBottom {
                // Cursor moved below bar area — show bar
                isBarHidden = false
                fadeBarWindows(hide: false)
            }
            // Cancel any pending hide timer
            dwellTimer?.invalidate()
            dwellTimer = nil
        }
    }

    // MARK: - Fullscreen Detection

    private func observeFullscreenPreference() {
        withObservationTracking {
            _ = PreferencesModel.shared.hideInFullscreen
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFullscreenState()
                self?.observeFullscreenPreference()
            }
        }
        applyFullscreenState()
    }

    private func applyFullscreenState() {
        let enabled = PreferencesModel.shared.hideInFullscreen
        if enabled, spaceObserver == nil {
            installFullscreenObservers()
            updateFullscreenVisibility()
        } else if !enabled {
            removeFullscreenObservers()
            restoreFullscreenHiddenWindows()
        }
    }

    private func installFullscreenObservers() {
        removeFullscreenObservers()
        let nc = NSWorkspace.shared.notificationCenter
        spaceObserver = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFullscreenVisibility()
            }
        }
        appActivationObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFullscreenVisibility()
            }
        }
    }

    private func removeFullscreenObservers() {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }

    private func restoreFullscreenHiddenWindows() {
        for index in fullscreenHiddenIndices {
            guard index < barWindows.count else {
                continue
            }
            showBarWindow(barWindows[index])
        }
        fullscreenHiddenIndices.removeAll()
    }

    private func updateFullscreenVisibility() {
        guard PreferencesModel.shared.hideInFullscreen else {
            return
        }

        let screens = NSScreen.screens
        let fullscreenIndices = FullscreenDetector.fullscreenScreenIndices(for: screens)

        for index in screens.indices {
            guard index < barWindows.count else {
                continue
            }
            let window = barWindows[index]

            if fullscreenIndices.contains(index) {
                if window.isVisible {
                    window.orderOut(nil)
                    fullscreenHiddenIndices.insert(index)
                }
            } else if fullscreenHiddenIndices.contains(index) {
                fullscreenHiddenIndices.remove(index)
                showBarWindow(window)
            }
        }
    }

    private func showBarWindow(_ window: BarWindow) {
        window.orderFrontRegardless()
        window.alphaValue = isBarHidden ? 0 : 1
    }

    private func fadeBarWindows(hide: Bool) {
        let duration = PreferencesModel.shared.autoHideFadeDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            for window in barWindows {
                window.animator().alphaValue = hide ? 0 : 1
            }
        }
    }

    func teardown() {
        rebuildTask?.cancel()
        rebuildTask = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        dwellTimer?.invalidate()
        dwellTimer = nil
        removeFullscreenObservers()
        fullscreenHiddenIndices.removeAll()
        ToastManager.shared.dismissAll()
        registry.stopAll()
        barWindows.forEach { $0.orderOut(nil) }
        barWindows.removeAll()
    }
}
