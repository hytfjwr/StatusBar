import AppKit
import StatusBarKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var windowStates: [BarWindowState] = []
    private let registry = WidgetRegistry.shared
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
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
                self?.createBarWindows()
            }
        }

        ConfigLoader.shared.onMonitorConfigDidChange = { [weak self] in
            self?.applyMonitorConfigs()
        }

        observeBarDimensions()
        observeShadowPreferences()
        observeTintPreferences()
        observeBehaviorPreferences()
        observeFullscreenPreference()
    }

    private func createBarWindows() {
        for windowState in windowStates {
            windowState.invalidateDwellTimer()
            windowState.window.orderOut(nil)
        }
        windowStates.removeAll()
        fullscreenHiddenIndices.removeAll()

        let rules = ConfigLoader.shared.currentConfig.monitors
        let globalAutoHide = PreferencesModel.shared.autoHideEnabled

        for (index, screen) in NSScreen.screens.enumerated() {
            let resolved = MonitorConfigResolver.resolve(
                screenName: screen.localizedName,
                rules: rules,
                globalAutoHide: globalAutoHide
            )
            let window = BarWindow(screen: screen)
            applyContentView(to: window, screenIndex: index, config: resolved)
            window.orderFrontRegardless()
            windowStates.append(BarWindowState(window: window, screen: screen, resolvedConfig: resolved))
        }

        updateFullscreenVisibility()
        setupToastManager()
        applyAutoHideState()
    }

    /// Re-resolve per-monitor configs without rebuilding windows (called on config hot-reload).
    private func applyMonitorConfigs() {
        let rules = ConfigLoader.shared.currentConfig.monitors
        let globalAutoHide = PreferencesModel.shared.autoHideEnabled

        for (index, state) in windowStates.enumerated() {
            let resolved = MonitorConfigResolver.resolve(
                screenName: state.screen.localizedName,
                rules: rules,
                globalAutoHide: globalAutoHide
            )

            // If auto-hide was disabled for this window, restore it
            if !resolved.autoHide, state.isHidden {
                state.isHidden = false
                state.invalidateDwellTimer()
                fadeWindow(state.window, hide: false)
            }

            let oldConfig = state.resolvedConfig
            state.resolvedConfig = resolved

            if resolved.widgetFilter != oldConfig.widgetFilter {
                applyContentView(to: state.window, screenIndex: index, config: resolved)
            }
        }

        applyAutoHideState()
    }

    private func setupToastManager() {
        guard let primary = windowStates.first, let screen = NSScreen.screens.first else {
            return
        }
        ToastManager.shared.reposition(anchoredTo: primary.window, on: screen)
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
                self?.windowStates.forEach { GlassEffect.applyShadow(to: $0.window) }
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
                self?.windowStates.forEach { $0.window.updateTint() }
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
                // Global autoHide changed — re-resolve all monitors
                self?.applyMonitorConfigs()
                self?.observeBehaviorPreferences()
            }
        }
        applyAutoHideState()
    }

    private func applyAutoHideState() {
        let anyAutoHide = windowStates.contains { $0.resolvedConfig.autoHide }

        if anyAutoHide, mouseMonitor == nil {
            installMouseMonitor()
        } else if !anyAutoHide {
            removeMouseMonitor()
            for state in windowStates where state.isHidden {
                state.isHidden = false
                state.invalidateDwellTimer()
                fadeWindow(state.window, hide: false)
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
        for state in windowStates {
            state.invalidateDwellTimer()
        }
    }

    // MARK: - Menu Bar Auto-Hide Detection

    private func handleMouseMove() {
        let mouseLocation = NSEvent.mouseLocation
        let barHeight = Theme.barHeight
        let barYOffset = Theme.barYOffset
        for state in windowStates {
            guard state.screen.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) else {
                continue
            }
            guard state.resolvedConfig.autoHide else {
                break
            }

            let mouseY = mouseLocation.y
            let screenTop = state.screen.frame.maxY
            let distanceFromTop = screenTop - mouseY

            if distanceFromTop <= 2 {
                // Cursor at the very top edge — start dwell timer to hide
                if !state.isHidden, state.dwellTimer == nil {
                    let dwellTime = PreferencesModel.shared.autoHideDwellTime
                    state.dwellTimer = Timer.scheduledTimer(
                        withTimeInterval: dwellTime, repeats: false
                    ) { [weak self, weak state] _ in
                        Task { @MainActor in
                            guard let self, let state else {
                                return
                            }
                            state.isHidden = true
                            self.fadeWindow(state.window, hide: true)
                        }
                    }
                }
            } else {
                let barBottom = screenTop - barHeight - barYOffset
                if state.isHidden, mouseY < barBottom {
                    // Cursor moved below bar area — show bar
                    state.isHidden = false
                    fadeWindow(state.window, hide: false)
                }
                // Cancel any pending hide timer
                state.invalidateDwellTimer()
            }
            break
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
            guard index < windowStates.count else {
                continue
            }
            showBarWindow(windowStates[index])
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
            guard index < windowStates.count else {
                continue
            }
            let state = windowStates[index]

            if fullscreenIndices.contains(index) {
                if state.window.isVisible {
                    state.window.orderOut(nil)
                    fullscreenHiddenIndices.insert(index)
                }
            } else if fullscreenHiddenIndices.contains(index) {
                fullscreenHiddenIndices.remove(index)
                showBarWindow(state)
            }
        }
    }

    private func showBarWindow(_ state: BarWindowState) {
        state.window.orderFrontRegardless()
        state.window.alphaValue = state.isHidden ? 0 : 1
    }

    private func applyContentView(to window: BarWindow, screenIndex: Int, config: MonitorConfig) {
        let contentView = BarContentView(registry: registry, screenIndex: screenIndex)
            .environment(\.widgetFilter, config.widgetFilter)
        window.setContent(contentView)
    }

    private func fadeWindow(_ window: BarWindow, hide: Bool) {
        let duration = PreferencesModel.shared.autoHideFadeDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            window.animator().alphaValue = hide ? 0 : 1
        }
    }

    func teardown() {
        rebuildTask?.cancel()
        rebuildTask = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        removeMouseMonitor()
        removeFullscreenObservers()
        fullscreenHiddenIndices.removeAll()
        ToastManager.shared.dismissAll()
        registry.stopAll()
        for windowState in windowStates {
            windowState.invalidateDwellTimer()
            windowState.window.orderOut(nil)
        }
        windowStates.removeAll()
        ConfigLoader.shared.onMonitorConfigDidChange = nil
    }
}
