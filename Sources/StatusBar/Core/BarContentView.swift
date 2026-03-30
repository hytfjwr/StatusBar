import StatusBarKit
import SwiftUI

// MARK: - WidgetFilterKey

private struct WidgetFilterKey: EnvironmentKey {
    static let defaultValue: Set<String>? = nil
}

extension EnvironmentValues {
    var widgetFilter: Set<String>? {
        get { self[WidgetFilterKey.self] }
        set { self[WidgetFilterKey.self] = newValue }
    }
}

// MARK: - BarContentView

struct BarContentView: View {
    let registry: WidgetRegistry
    let screenIndex: Int

    @Environment(\.widgetFilter) private var widgetFilter

    private func filtered(_ widgets: [AnyStatusBarWidget]) -> [AnyStatusBarWidget] {
        guard let filter = widgetFilter else {
            return widgets
        }
        return widgets.filter { filter.contains($0.id) }
    }

    var body: some View {
        ZStack {
            // CENTER — absolutely centered on screen
            HStack(spacing: Theme.widgetSpacing) {
                ForEach(filtered(registry.centerWidgets)) { widget in
                    widget.body()
                        .transition(.widgetAppear)
                }
            }

            // LEFT & RIGHT — pinned to edges
            HStack(spacing: 0) {
                HStack(spacing: Theme.widgetSpacing) {
                    ForEach(filtered(registry.leftWidgets)) { widget in
                        widget.body()
                            .transition(.widgetAppear)
                    }
                }
                .padding(.leading, Theme.widgetPaddingH)

                Spacer()

                HStack(spacing: Theme.widgetSpacing) {
                    ForEach(filtered(registry.rightWidgets)) { widget in
                        widget.body()
                            .transition(.widgetAppear)
                    }
                }
                .padding(.trailing, Theme.widgetPaddingH)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.screenIndex, screenIndex)
    }
}
