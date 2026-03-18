import StatusBarKit
import SwiftUI

struct GeneralSection: View {
    @Bindable var model: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "General", resetAction: model.resetGeneral)

            GroupBox("Bar Dimensions") {
                VStack(spacing: 10) {
                    SliderRow(label: "Bar Height", value: $model.barHeight, range: 28 ... 56)
                    SliderRow(label: "Corner Radius", value: $model.barCornerRadius, range: 0 ... 24)
                    SliderRow(label: "Margin", value: $model.barMargin, range: 0 ... 24)
                    SliderRow(label: "Y Offset", value: $model.barYOffset, range: 0 ... 16)
                }
                .padding(8)
            }

            GroupBox("Widget Layout") {
                VStack(spacing: 10) {
                    SliderRow(label: "Widget Spacing", value: $model.widgetSpacing, range: 0 ... 16)
                    SliderRow(label: "Padding H", value: $model.widgetPaddingH, range: 0 ... 16)
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
