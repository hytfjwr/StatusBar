import StatusBarKit
import SwiftUI

struct TypographySection: View {
    @Bindable var model: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Typography", resetAction: model.resetTypography)

            GroupBox("Icon Font") {
                VStack(spacing: 10) {
                    SliderRow(label: "SF Icon Size", value: $model.iconFontSize, range: 8 ... 24, unit: "pt")
                }
                .padding(8)
            }

            GroupBox("Text Fonts") {
                VStack(spacing: 10) {
                    SliderRow(label: "Label Size", value: $model.labelFontSize, range: 8 ... 24, unit: "pt")
                    SliderRow(label: "Small Size", value: $model.smallFontSize, range: 6 ... 20, unit: "pt")
                    SliderRow(label: "Mono Size", value: $model.monoFontSize, range: 8 ... 24, unit: "pt")
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
