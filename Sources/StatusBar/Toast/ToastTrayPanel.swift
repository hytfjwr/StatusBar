import AppKit
import StatusBarKit
import SwiftUI

@MainActor
final class ToastTrayPanel: NSPanel {
    private var hostingView: NSHostingView<ToastTrayView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 316, height: 100),
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
    }

    func setContent(_ view: ToastTrayView) {
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        hosting.layer?.cornerRadius = Theme.popupCornerRadius
        hosting.layer?.masksToBounds = true
        hostingView = hosting

        let glassView = GlassEffect.makeView(
            frame: .zero,
            cornerRadius: Theme.popupCornerRadius
        )
        glassView.wantsLayer = true
        glassView.layer?.masksToBounds = true
        glassView.contentView = hosting

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glassView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ])

        contentView = glassView
        GlassEffect.applyTint(to: glassView)
        GlassEffect.applyShadow(to: self)
    }

    func reposition(anchoredBelow barFrame: NSRect, on screen: NSScreen) {
        guard let hosting = hostingView else {
            return
        }
        let fittingSize = hosting.fittingSize

        let panelX = screen.frame.midX - fittingSize.width / 2
        let panelY = barFrame.minY - fittingSize.height - 6

        setFrame(
            NSRect(x: panelX, y: panelY, width: fittingSize.width, height: fittingSize.height),
            display: true
        )
    }

    func updateTint() {
        guard let glassView = contentView as? NSGlassEffectView else {
            return
        }
        GlassEffect.applyTint(to: glassView)
    }

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
