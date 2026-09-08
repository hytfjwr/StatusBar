import StatusBarKit
import SwiftUI

// MARK: - BarContentView

struct BarContentView: View {
    let registry: WidgetRegistry
    let screenIndex: Int

    /// Read from the service rather than the inherited `NSAppearance` so the switch
    /// arrives as one observable change that `.animation(_:value:)` can fade.
    private var isDark: Bool {
        AppearanceService.shared.isDark
    }

    var body: some View {
        ZStack {
            // CENTER — absolutely centered on screen
            HStack(spacing: Theme.widgetSpacing) {
                ForEach(registry.centerWidgets) { widget in
                    widget.body()
                        .transition(.widgetAppear)
                }
            }

            // LEFT & RIGHT — pinned to edges
            HStack(spacing: 0) {
                HStack(spacing: Theme.widgetSpacing) {
                    ForEach(registry.leftWidgets) { widget in
                        widget.body()
                            .transition(.widgetAppear)
                    }
                }
                .padding(.leading, Theme.widgetPaddingH)

                Spacer()

                HStack(spacing: Theme.widgetSpacing) {
                    ForEach(registry.rightWidgets) { widget in
                        widget.body()
                            .transition(.widgetAppear)
                    }
                }
                .padding(.trailing, Theme.widgetPaddingH)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .animation(.easeInOut(duration: AppearanceService.fadeDuration), value: isDark)
        .environment(\.screenIndex, screenIndex)
    }
}
