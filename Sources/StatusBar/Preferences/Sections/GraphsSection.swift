import StatusBarKit
import SwiftUI

struct GraphsSection: View {
    @Bindable var model: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Graphs", resetAction: model.resetGraphs)

            GroupBox("Dimensions") {
                VStack(spacing: 10) {
                    SliderRow(label: "Width", value: $model.graphWidth, range: 20 ... 60)
                    SliderRow(label: "Height", value: $model.graphHeight, range: 10 ... 30)
                    HStack {
                        Text("Data Points")
                            .frame(width: 120, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(model.graphDataPoints) },
                                set: { model.graphDataPoints = Int($0) }
                            ),
                            in: 20 ... 100,
                            step: 5
                        )
                        Text("\(model.graphDataPoints)")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .padding(8)
            }

            GroupBox("Colors") {
                VStack(spacing: 10) {
                    ColorHexRow(label: "CPU Graph", hex: $model.cpuGraphHex)
                    ColorHexRow(label: "Memory Graph", hex: $model.memoryGraphHex)
                }
                .padding(8)
            }

            GroupBox("Preview") {
                HStack(spacing: 24) {
                    graphPreview(label: "CPU", color: model.cpuGraphColor)
                    graphPreview(label: "Memory", color: model.memoryGraphColor)
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func graphPreview(label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: model.graphWidth, height: model.graphHeight)
                // Sample wave
                Path { path in
                    let w = model.graphWidth
                    let h = model.graphHeight
                    let points = 10
                    path.move(to: CGPoint(x: 0, y: h * 0.5))
                    for i in 0 ... points {
                        let x = w * CGFloat(i) / CGFloat(points)
                        let y = h * (0.3 + 0.4 * sin(Double(i) * 0.8))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color, lineWidth: 1)
                .frame(width: model.graphWidth, height: model.graphHeight)
            }
        }
    }
}
