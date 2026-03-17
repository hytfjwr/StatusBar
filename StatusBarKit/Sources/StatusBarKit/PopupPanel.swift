import AppKit
import SwiftUI

@MainActor
public final class PopupPanel: NSPanel {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentHostingView: NSHostingView<AnyView>?
    public var onHide: (() -> Void)?
    private var lastHideTime: Date = .distantPast
    private var lastTriggerFrame: NSRect?
    private var lastScreen: NSScreen?

    /// Returns true if the popup was hidden very recently (within 300ms).
    /// Used to prevent the race condition where a click monitor hides the popup
    /// and then an onTapGesture immediately re-opens it.
    public var wasRecentlyHidden: Bool {
        Date().timeIntervalSince(lastHideTime) < 0.3
    }

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
    }

    public func showPopup(relativeTo triggerFrame: NSRect, on screen: NSScreen, content: some View) {
        // Prevent reopening if the popup was just closed by a click monitor.
        // This avoids the race where the monitor's hidePopup() fires before
        // SwiftUI's onTapGesture, causing the popup to immediately reopen.
        if wasRecentlyHidden { return }

        lastTriggerFrame = triggerFrame
        lastScreen = screen

        if currentHostingView != nil {
            // View hierarchy already exists — update content and reposition only
            updateContent(content)
        } else {
            // First show — full setup
            setupViewHierarchy(with: content)
        }

        repositionPopup(relativeTo: triggerFrame, on: screen)
        PopupManager.shared.willShow(self)
        makeKeyAndOrderFront(nil)
        startMonitoringClicks()
    }

    private func setupViewHierarchy(with content: some View) {
        let wrappedContent = AnyView(content.focusEffectDisabled())
        let hostingView = NSHostingView(rootView: wrappedContent)
        hostingView.focusRingType = .none
        currentHostingView = hostingView

        let glassView = GlassEffect.makeView(
            frame: .zero,
            cornerRadius: Theme.popupCornerRadius
        )

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false
        hostingView.layer?.cornerRadius = Theme.popupCornerRadius
        hostingView.layer?.masksToBounds = true

        glassView.wantsLayer = true
        glassView.layer?.masksToBounds = true

        glassView.contentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ])

        contentView = glassView
        GlassEffect.applyShadow(to: self)
    }

    private func repositionPopup(relativeTo triggerFrame: NSRect, on screen: NSScreen) {
        guard let hostingView = currentHostingView else { return }
        let fittingSize = hostingView.fittingSize

        // triggerFrame is already in screen coordinates.
        // Position popup centered below the trigger, with a 6pt gap below the bar.
        var popupX = triggerFrame.midX - fittingSize.width / 2
        let popupY = triggerFrame.minY - fittingSize.height - 6

        // Clamp horizontally to keep popup within screen
        let screenFrame = screen.frame
        let minX = screenFrame.origin.x + 4
        let maxX = screenFrame.origin.x + screenFrame.width - fittingSize.width - 4
        popupX = max(minX, min(popupX, maxX))

        // Clamp vertically: if popup would go below visible area, place it above the bar
        let visibleFrame = screen.visibleFrame
        var popupYFinal = popupY
        if popupY < visibleFrame.origin.y {
            popupYFinal = triggerFrame.maxY + 4
        }

        let popupFrame = NSRect(x: popupX, y: popupYFinal, width: fittingSize.width, height: fittingSize.height)
        setFrame(popupFrame, display: true)
    }

    /// Update the popup content in place without recreating the panel.
    public func updateContent(_ content: some View) {
        currentHostingView?.rootView = AnyView(content.focusEffectDisabled())
    }

    /// Resize the popup to fit its current content. Call after content changes
    /// that affect the popup's size (e.g. accordion expand/collapse).
    public func resizeToFitContent() {
        guard let triggerFrame = lastTriggerFrame, let screen = lastScreen else { return }
        repositionPopup(relativeTo: triggerFrame, on: screen)
    }

    public func hidePopup() {
        lastHideTime = Date()
        orderOut(nil)
        stopMonitoringClicks()
        currentHostingView = nil
        onHide?()
        PopupManager.shared.didHide(self)
    }

    private func startMonitoringClicks() {
        stopMonitoringClicks()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.hidePopup()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else {
                return event
            }
            // Use the event's source window for coordinate conversion,
            // not the popup panel, since the event may originate from BarWindow.
            let sourceWindow = event.window ?? self
            let locationInScreen = sourceWindow.convertPoint(toScreen: event.locationInWindow)
            if !frame.contains(locationInScreen) {
                hidePopup()
            }
            return event
        }
    }

    private func stopMonitoringClicks() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m); globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m); localMonitor = nil
        }
    }

    /// nonactivatingPanel prevents stealing focus from other apps.
    /// canBecomeKey must be true for cursor rects (addCursorRect) to work.
    override public var canBecomeKey: Bool {
        true
    }

    override public var canBecomeMain: Bool {
        false
    }

    /// Returns the screen where the mouse cursor is currently located.
    public static func screenForMouseLocation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    /// Returns a trigger frame centered on the current mouse X position within the bar,
    /// along with the screen. Use this instead of hardcoding widget positions so that
    /// popups always appear under the clicked widget regardless of layout order.
    public static func barTriggerFrame(width: CGFloat = 40) -> (frame: NSRect, screen: NSScreen)? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screenForMouseLocation() else { return nil }

        let barFrame = NSRect(
            x: mouseLocation.x - width / 2,
            y: screen.frame.maxY - Theme.barHeight - Theme.barYOffset,
            width: width,
            height: Theme.barHeight
        )
        return (barFrame, screen)
    }
}
