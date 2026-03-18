import StatusBarKit
import SwiftUI

// MARK: - PreferencesView

struct PreferencesView: View {
    @Bindable var model: PreferencesModel
    @State private var selectedSection: PreferencesSection = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(PreferencesSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .frame(width: 170)

            Divider()

            // Detail
            ScrollView {
                detailContent
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .general:
            GeneralSection(model: model)
        case .behavior:
            BehaviorSection(model: model)
        case .widgets:
            WidgetsSection(registry: WidgetRegistry.shared)
        case .appearance:
            AppearanceSection(model: model)
        case .typography:
            TypographySection(model: model)
        case .graphs:
            GraphsSection(model: model)
        case .notifications:
            NotificationsSection(model: model)
        case .plugins:
            PluginsSection()
        case .presets:
            PresetsSection()
        case .about:
            AboutSection()
        }
    }
}

// MARK: - PreferencesSection

enum PreferencesSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case behavior
    case widgets
    case appearance
    case typography
    case graphs
    case notifications
    case plugins
    case presets
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "General"
        case .behavior: "Behavior"
        case .widgets: "Widgets"
        case .appearance: "Appearance"
        case .typography: "Typography"
        case .graphs: "Graphs"
        case .notifications: "Notifications"
        case .plugins: "Plugins"
        case .presets: "Presets"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .behavior: "gearshape"
        case .widgets: "square.grid.2x2"
        case .appearance: "paintbrush"
        case .typography: "textformat"
        case .graphs: "chart.xyaxis.line"
        case .notifications: "bell"
        case .plugins: "puzzlepiece.extension"
        case .presets: "square.on.square.dashed"
        case .about: "info.circle"
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    let resetAction: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("Reset to Defaults") {
                resetAction()
            }
            .controlSize(.small)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - SliderRow

struct SliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let unit: String

    init(label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat = 1, unit: String = "px") {
        self.label = label
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text("\(Int(value))\(unit)")
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - DoubleSliderRow

struct DoubleSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let fractionDigits: Int

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        unit: String = "",
        fractionDigits: Int = 0
    ) {
        self.label = label
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.fractionDigits = fractionDigits
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(formattedValue)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }

    private var formattedValue: String {
        if fractionDigits == 0 {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.\(fractionDigits)f\(unit)", value)
    }
}

// MARK: - ToggleRow

struct ToggleRow: View {
    let label: String
    @Binding var value: Bool

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            Toggle("", isOn: $value)
                .labelsHidden()
            Spacer()
        }
    }
}

// MARK: - OpacityRow

struct OpacityRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range, step: 0.05)
            Text("\(Int(value * 100))%")
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - ColorHexRow

struct ColorHexRow: View {
    let label: String
    @Binding var hex: UInt32

    @State private var selectedColor: Color

    init(label: String, hex: Binding<UInt32>) {
        self.label = label
        _hex = hex
        _selectedColor = State(initialValue: Color(hex: hex.wrappedValue))
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: selectedColor) { _, newColor in
                    hex = newColor.toHex()
                }
            Text(String(format: "#%06X", hex))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Color Hex Conversion

extension Color {
    func toHex() -> UInt32 {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return 0x000000
        }
        let r = !components.isEmpty ? components[0] : 0
        let g = components.count > 1 ? components[1] : 0
        let b = components.count > 2 ? components[2] : 0
        return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    }
}
