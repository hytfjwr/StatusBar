import StatusBarKit
import SwiftUI

// MARK: - BarContentView

struct BarContentView: View {
    let registry: WidgetRegistry
    let screenIndex: Int

    var body: some View {
        ZStack {
            // CENTER — absolutely centered on screen
            HStack(spacing: Theme.widgetSpacing) {
                ForEach(registry.centerWidgets) { widget in
                    widget.body()
                }
            }

            // LEFT & RIGHT — pinned to edges
            HStack(spacing: 0) {
                HStack(spacing: Theme.widgetSpacing) {
                    ForEach(registry.leftWidgets) { widget in
                        widget.body()
                    }
                }
                .padding(.leading, Theme.widgetPaddingH)

                Spacer()

                HStack(spacing: Theme.widgetSpacing) {
                    ForEach(registry.rightWidgets) { widget in
                        widget.body()
                    }
                }
                .padding(.trailing, Theme.widgetPaddingH)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.screenIndex, screenIndex)
    }
}
