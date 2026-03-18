import StatusBarKit
import SwiftUI

struct AppearanceSection: View {
    @Bindable var model: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Appearance", resetAction: model.resetAppearance)

            GroupBox("Glass Tint (Blur Density)") {
                VStack(spacing: 10) {
                    OpacityRow(label: "Tint Opacity", value: $model.barTintOpacity, range: 0 ... 0.8)
                    ColorHexRow(label: "Tint Color", hex: $model.barTintHex)
                }
                .padding(8)
            }

            GroupBox("Drop Shadow") {
                VStack(spacing: 10) {
                    ToggleRow(label: "Enabled", value: $model.shadowEnabled)
                }
                .padding(8)
            }

            GroupBox("Accent") {
                VStack(spacing: 10) {
                    ColorHexRow(label: "Accent Color", hex: $model.accentHex)
                }
                .padding(8)
            }

            GroupBox("Text Opacity") {
                VStack(spacing: 10) {
                    OpacityRow(label: "Primary", value: $model.textPrimaryOpacity, range: 0.5 ... 1)
                    OpacityRow(label: "Secondary", value: $model.textSecondaryOpacity, range: 0.2 ... 1)
                    OpacityRow(label: "Tertiary", value: $model.textTertiaryOpacity, range: 0.1 ... 1)
                }
                .padding(8)
            }

            GroupBox("Semantic Colors") {
                VStack(spacing: 10) {
                    ColorHexRow(label: "Green", hex: $model.greenHex)
                    ColorHexRow(label: "Yellow", hex: $model.yellowHex)
                    ColorHexRow(label: "Red", hex: $model.redHex)
                    ColorHexRow(label: "Cyan", hex: $model.cyanHex)
                    ColorHexRow(label: "Purple", hex: $model.purpleHex)
                }
                .padding(8)
            }

            GroupBox("Popup") {
                VStack(spacing: 10) {
                    SliderRow(label: "Corner Radius", value: $model.popupCornerRadius, range: 0 ... 24)
                    SliderRow(label: "Padding", value: $model.popupPadding, range: 4 ... 24)
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
