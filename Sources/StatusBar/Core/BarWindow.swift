import AppKit
import StatusBarKit
import SwiftUI

@MainActor
final class BarWindow: NSPanel {
    /// The glass backdrop currently showing. Replaced by `fadeAppearance` cross-fades.
    private var glassView: NSGlassEffectView
    private var hostingView: NSView?
    /// Glass being faded out; kept so an interrupted fade can be finished early.
    private var outgoingGlassView: NSGlassEffectView?
    private var hostingConstraints: [NSLayoutConstraint] = []
    /// Identifies the fade in flight so a superseded animation cannot land on top of a newer one.
    private var fadeToken = 0

    init(screen: NSScreen) {
        let screenFrame = screen.frame
        let barW = screenFrame.width - Theme.barMargin * 2
        let barX = screenFrame.origin.x + Theme.barMargin
        let barY = screenFrame.origin.y + screenFrame.height - Theme.barHeight - Theme.barYOffset
        let bounds = NSRect(x: 0, y: 0, width: barW, height: Theme.barHeight)

        // Liquid glass background
        glassView = GlassEffect.makeView(frame: bounds, cornerRadius: Theme.barCornerRadius)

        super.init(
            contentRect: NSRect(x: barX, y: barY, width: barW, height: Theme.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Notification Center = 21, Dock = 20; stay below notifications
        level = NSWindow.Level(rawValue: 20)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Transparent container so two glass layers can cross-fade on appearance changes
        let container = NSView(frame: bounds)
        container.autoresizesSubviews = true
        contentView = container

        glassView.autoresizingMask = [.width, .height]
        // Pin the appearance so a system switch does not repaint this layer instantly
        glassView.appearance = AppearanceService.nsAppearance(isDark: AppearanceService.shared.isDark)
        container.addSubview(glassView)

        // Tint overlay for adjustable blur density
        GlassEffect.applyTint(to: glassView)

        // Soft shadow
        GlassEffect.applyShadow(to: self)
    }

    func setContent(_ view: some View) {
        let hostingView = NSHostingView(rootView: view)
        // Ensure hosting view is transparent so glass shines through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.hostingView = hostingView

        embedContentInGlass()
    }

    func updateTint() {
        GlassEffect.applyTint(to: glassView)
    }

    func updateFrame(for screen: NSScreen) {
        let screenFrame = screen.frame
        let barW = screenFrame.width - Theme.barMargin * 2
        let barX = screenFrame.origin.x + Theme.barMargin
        let barY = screenFrame.origin.y + screenFrame.height - Theme.barHeight - Theme.barYOffset

        setFrame(NSRect(x: barX, y: barY, width: barW, height: Theme.barHeight), display: true)
    }

    // MARK: - Appearance Transition

    /// Cross-fade the glass backdrop into the given appearance.
    ///
    /// The SwiftUI content fades its own colors over the same duration (see
    /// `BarContentView`), so it is lifted above both glass layers while they
    /// cross-fade and re-embedded once the outgoing layer is gone.
    func fadeAppearance(isDark: Bool, duration: TimeInterval) {
        guard let container = contentView else {
            return
        }

        // A fade is still running — land it before starting the next one
        finishAppearanceFade()
        fadeToken += 1
        let token = fadeToken

        let outgoing = glassView
        let incoming = GlassEffect.makeView(frame: container.bounds, cornerRadius: Theme.barCornerRadius)
        incoming.autoresizingMask = [.width, .height]
        incoming.appearance = AppearanceService.nsAppearance(isDark: isDark)
        incoming.alphaValue = 0
        container.addSubview(incoming, positioned: .above, relativeTo: outgoing)
        GlassEffect.applyTint(to: incoming)

        glassView = incoming
        outgoingGlassView = outgoing
        liftContentAboveGlass(from: outgoing, into: container)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outgoing.animator().alphaValue = 0
            incoming.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let window = self else {
                return
            }
            MainActor.assumeIsolated {
                // A newer fade superseded this one — let that one land instead
                guard token == window.fadeToken else {
                    return
                }
                window.finishAppearanceFade()
            }
        }
    }

    /// Drop the outgoing glass layer and put the content back inside the glass.
    private func finishAppearanceFade() {
        guard let outgoing = outgoingGlassView else {
            return
        }
        outgoingGlassView = nil
        outgoing.removeFromSuperview()
        glassView.alphaValue = 1
        embedContentInGlass()
    }

    private func embedContentInGlass() {
        guard let hostingView else {
            return
        }
        NSLayoutConstraint.deactivate(hostingConstraints)

        // NSGlassEffectView.contentView embeds content inside the glass
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView = hostingView

        hostingConstraints = [
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostingConstraints)
    }

    private func liftContentAboveGlass(from glass: NSGlassEffectView, into container: NSView) {
        guard let hostingView else {
            return
        }
        NSLayoutConstraint.deactivate(hostingConstraints)

        glass.contentView = nil
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)

        hostingConstraints = [
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostingConstraints)
    }

    /// Bypass macOS constraint that pushes windows below the menu bar / notch
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
