import AppKit
import SwiftUI

/// A SwiftUI view that displays the actual macOS app icon for a given app name.
/// Falls back to a generic SF Symbol if the native icon is not available.
public struct AppIconView: View {
    public let appName: String
    public let size: CGFloat

    public init(appName: String, size: CGFloat) {
        self.appName = appName
        self.size = size
    }

    public var body: some View {
        if let nsImage = AppIconProvider.shared.icon(for: appName) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.75))
        }
    }
}
