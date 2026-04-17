import AppKit
import StatusBarKit
import SwiftUI

@MainActor
final class BarWindow: NSPanel {
    init(screen: NSScreen) {
        let screenFrame = screen.frame
        let barW = screenFrame.width - Theme.barMargin * 2
        let barX = screenFrame.origin.x + Theme.barMargin
        let barY = screenFrame.origin.y + screenFrame.height - Theme.barHeight - Theme.barYOffset

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

        // Liquid glass background
        let glassView = GlassEffect.makeView(
            frame: NSRect(x: 0, y: 0, width: barW, height: Theme.barHeight),
            cornerRadius: Theme.barCornerRadius
        )
        contentView = glassView

        // Tint overlay for adjustable blur density
        GlassEffect.applyTint(to: glassView)

        // Soft shadow
        GlassEffect.applyShadow(to: self)
    }

    func setContent(_ view: some View) {
        guard let glassView = contentView as? NSGlassEffectView else {
            return
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Ensure hosting view is transparent so glass shines through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        // NSGlassEffectView.contentView embeds content inside the glass
        glassView.contentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ])
    }

    func updateTint() {
        guard let glassView = contentView as? NSGlassEffectView else {
            return
        }
        GlassEffect.applyTint(to: glassView)
    }

    func updateFrame(for screen: NSScreen) {
        let screenFrame = screen.frame
        let barW = screenFrame.width - Theme.barMargin * 2
        let barX = screenFrame.origin.x + Theme.barMargin
        let barY = screenFrame.origin.y + screenFrame.height - Theme.barHeight - Theme.barYOffset

        setFrame(NSRect(x: barX, y: barY, width: barW, height: Theme.barHeight), display: true)
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
