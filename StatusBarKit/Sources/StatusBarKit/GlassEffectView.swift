import AppKit

/// Native Liquid Glass effect using NSGlassEffectView (macOS 26+).
@MainActor
public enum GlassEffect {
    /// Build a native Liquid Glass view for a given frame.
    public static func makeView(frame: NSRect, cornerRadius: CGFloat = Theme.barCornerRadius) -> NSGlassEffectView {
        let view = NSGlassEffectView(frame: frame)
        view.cornerRadius = cornerRadius
        return view
    }

    /// Apply or update the tint overlay on a glass view.
    /// The overlay simulates adjustable blur density by adding a semi-transparent color layer.
    public static func applyTint(to glassView: NSGlassEffectView) {
        // Remove existing tint layer if any (identified by accessibilityIdentifier)
        glassView.subviews
            .filter { $0.accessibilityIdentifier() == "glassTintOverlay" }
            .forEach { $0.removeFromSuperview() }

        let opacity = Theme.barTintOpacity
        guard opacity > 0 else { return }

        let hex = Theme.barTintHex
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0

        let tintView = NSView(frame: glassView.bounds)
        tintView.setAccessibilityIdentifier("glassTintOverlay")
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(
            srgbRed: r, green: g, blue: b, alpha: CGFloat(opacity)
        ).cgColor
        tintView.layer?.cornerRadius = glassView.cornerRadius as CGFloat

        // Insert behind contentView but inside the glass
        glassView.addSubview(tintView, positioned: .below, relativeTo: glassView.contentView)
    }

    /// Apply shadow to a window.
    /// NSGlassEffectView provides its own depth and lighting —
    /// only use the system shadow; avoid manual layer shadows that flatten the glass.
    public static func applyShadow(to window: NSPanel) {
        window.hasShadow = Theme.shadowEnabled
    }
}
