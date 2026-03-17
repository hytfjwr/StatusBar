import SwiftUI

// MARK: - Theme

public enum Theme {
    @MainActor private static var provider: (any ThemeProvider)?

    /// Call once at app launch to inject the concrete theme provider.
    @MainActor public static func configure(provider: any ThemeProvider) {
        self.provider = provider
    }

    @MainActor private static var p: any ThemeProvider {
        guard let provider else {
            fatalError("Theme.configure(provider:) must be called before accessing Theme properties")
        }
        return provider
    }

    // Bar
    @MainActor public static var barHeight: CGFloat { p.barHeight }
    @MainActor public static var barMargin: CGFloat { p.barMargin }
    @MainActor public static var barYOffset: CGFloat { p.barYOffset }
    @MainActor public static var barCornerRadius: CGFloat { p.barCornerRadius }

    // Widget spacing & padding
    @MainActor public static var widgetSpacing: CGFloat { p.widgetSpacing }
    @MainActor public static var widgetPaddingH: CGFloat { p.widgetPaddingH }

    // Popup
    @MainActor public static var popupCornerRadius: CGFloat { p.popupCornerRadius }
    @MainActor public static var popupPadding: CGFloat { p.popupPadding }
    public static let popupItemCornerRadius: CGFloat = 6

    // Glass tint
    @MainActor public static var barTintHex: UInt32 { p.barTintHex }
    @MainActor public static var barTintOpacity: Double { p.barTintOpacity }

    // Shadow
    @MainActor public static var shadowEnabled: Bool { p.shadowEnabled }

    // Colors
    @MainActor public static var memoryGraph: Color { p.memoryGraphColor }
    @MainActor public static var cpuGraph: Color { p.cpuGraphColor }

    // Semantic Colors
    @MainActor public static var green: Color { p.greenColor }
    @MainActor public static var yellow: Color { p.yellowColor }
    @MainActor public static var red: Color { p.redColor }
    @MainActor public static var cyan: Color { p.cyanColor }
    @MainActor public static var purple: Color { p.purpleColor }
    // Text hierarchy
    @MainActor public static var primary: Color { p.primaryColor }
    @MainActor public static var secondary: Color { p.secondaryColor }
    @MainActor public static var tertiary: Color { p.tertiaryColor }
    public static let separator = Color(.separatorColor)
    @MainActor public static var accentBlue: Color { p.accentColor }

    // Fonts
    @MainActor public static var sfIconFont: Font { p.sfIconFont }
    @MainActor public static var labelFont: Font { p.labelFont }
    @MainActor public static var smallFont: Font { p.smallFont }
    @MainActor public static var monoFont: Font { p.monoFont }
    @MainActor public static var popupLabelFont: Font { p.popupLabelFont }

    // Graph dimensions
    @MainActor public static var graphWidth: CGFloat { p.graphWidth }
    @MainActor public static var graphHeight: CGFloat { p.graphHeight }
    @MainActor public static var graphDataPoints: Int { p.graphDataPoints }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
