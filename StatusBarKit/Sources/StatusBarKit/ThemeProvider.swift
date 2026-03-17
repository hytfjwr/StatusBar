import SwiftUI

/// Protocol that decouples Theme from a concrete preferences implementation.
/// The host app provides a conforming type (e.g. PreferencesModel) at launch.
@MainActor
public protocol ThemeProvider: AnyObject {
    var barHeight: CGFloat { get }
    var barMargin: CGFloat { get }
    var barYOffset: CGFloat { get }
    var barCornerRadius: CGFloat { get }
    var widgetSpacing: CGFloat { get }
    var widgetPaddingH: CGFloat { get }
    var memoryGraphColor: Color { get }
    var cpuGraphColor: Color { get }
    var greenColor: Color { get }
    var yellowColor: Color { get }
    var redColor: Color { get }
    var cyanColor: Color { get }
    var purpleColor: Color { get }
    var accentColor: Color { get }
    var primaryColor: Color { get }
    var secondaryColor: Color { get }
    var tertiaryColor: Color { get }
    var sfIconFont: Font { get }
    var labelFont: Font { get }
    var smallFont: Font { get }
    var monoFont: Font { get }
    var popupLabelFont: Font { get }
    var graphWidth: CGFloat { get }
    var graphHeight: CGFloat { get }
    var graphDataPoints: Int { get }

    // Glass tint (simulates blur density)
    var barTintHex: UInt32 { get }
    var barTintOpacity: Double { get }

    // Shadow
    var shadowEnabled: Bool { get }

    // Popup
    var popupCornerRadius: CGFloat { get }
    var popupPadding: CGFloat { get }
}
