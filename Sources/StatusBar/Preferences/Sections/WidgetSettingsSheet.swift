import StatusBarKit
import SwiftUI

// MARK: - WidgetSettingsSheet

struct WidgetSettingsSheet: View {
    let widgetID: String
    private let sheetSize: CGSize
    @Environment(\.dismiss) private var dismiss

    private static let defaultSize = CGSize(width: 360, height: 240)
    private static let minSize = CGSize(width: 280, height: 180)
    private static let maxSize = CGSize(width: 700, height: 600)

    init(widgetID: String) {
        self.widgetID = widgetID
        if let preferred = WidgetRegistry.shared.preferredSettingsSize(for: widgetID) {
            sheetSize = CGSize(
                width: min(max(preferred.width, Self.minSize.width), Self.maxSize.width),
                height: min(max(preferred.height, Self.minSize.height), Self.maxSize.height)
            )
        } else {
            sheetSize = Self.defaultSize
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(displayName) Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .controlSize(.small)
            }
            .padding()

            Divider()

            // Settings content
            ScrollView {
                settingsContent
                    .padding()
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    private var settingsContent: some View {
        WidgetRegistry.shared.settingsView(for: widgetID)
    }

    private var displayName: String {
        WidgetRegistry.displayName(for: widgetID)
    }
}

// MARK: - TimeWidgetSettings

struct TimeWidgetSettings: View {
    @State private var format: String

    init() {
        _format = State(initialValue: TimeSettings.shared.format)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Format")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Format", selection: $format) {
                Text("24h (HH:mm)").tag("HH:mm")
                Text("24h with seconds (HH:mm:ss)").tag("HH:mm:ss")
                Text("12h (h:mm a)").tag("h:mm a")
            }
            .pickerStyle(.radioGroup)
            .onChange(of: format) { _, newValue in
                TimeSettings.shared.format = newValue
            }

            previewRow(format: format)
        }
    }
}

// MARK: - DateWidgetSettings

struct DateWidgetSettings: View {
    @State private var format: String
    @State private var showNextEventOnBar: Bool
    @State private var showNextEventInPopup: Bool
    @State private var notifyNextEvent: Bool
    @State private var notifyMinutesBefore: [Int]

    init() {
        _format = State(initialValue: DateSettings.shared.format)
        _showNextEventOnBar = State(initialValue: DateSettings.shared.showNextEventOnBar)
        _showNextEventInPopup = State(initialValue: DateSettings.shared.showNextEventInPopup)
        _notifyNextEvent = State(initialValue: DateSettings.shared.notifyNextEvent)
        _notifyMinutesBefore = State(initialValue: DateSettings.shared.notifyMinutesBefore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Format")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Format", selection: $format) {
                Text("EEE dd. MMM (Wed 12. Mar)").tag("EEE dd. MMM")
                Text("yyyy-MM-dd (2026-03-12)").tag("yyyy-MM-dd")
                Text("M/d (3/12)").tag("M/d")
                Text("MMM d, yyyy (Mar 12, 2026)").tag("MMM d, yyyy")
            }
            .pickerStyle(.radioGroup)
            .onChange(of: format) { _, newValue in
                DateSettings.shared.format = newValue
            }

            previewRow(format: format)

            Divider()

            Text("Next Event")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Show on Bar", isOn: $showNextEventOnBar)
                .onChange(of: showNextEventOnBar) { _, newValue in
                    DateSettings.shared.showNextEventOnBar = newValue
                }

            Text("Shows the next upcoming event with countdown and join button on the bar.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Toggle("Show in Popup", isOn: $showNextEventInPopup)
                .onChange(of: showNextEventInPopup) { _, newValue in
                    DateSettings.shared.showNextEventInPopup = newValue
                }

            Text("Shows the \"Next Up\" section at the top of the calendar popup.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Divider()

            Text("Toast Notification")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Notify before events", isOn: $notifyNextEvent)
                .onChange(of: notifyNextEvent) { _, newValue in
                    DateSettings.shared.notifyNextEvent = newValue
                }

            Text("Shows a toast notification before the next event starts.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            EventNotifyMinutesEditor(minutes: $notifyMinutesBefore)
                .disabled(!notifyNextEvent)
                .opacity(notifyNextEvent ? 1 : 0.5)
                .onChange(of: notifyMinutesBefore) { _, newValue in
                    DateSettings.shared.notifyMinutesBefore = newValue
                }
        }
    }
}

// MARK: - EventNotifyMinutesEditor

private struct EventNotifyMinutesEditor: View {
    @Binding var minutes: [Int]
    @State private var drafts: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notify before")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addEntry()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(minutes.count >= 10)
            }

            ForEach(minutes, id: \.self) { value in
                HStack(spacing: 8) {
                    TextField(
                        "min",
                        text: Binding(
                            get: { drafts[value] ?? String(value) },
                            set: { drafts[value] = $0 }
                        )
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitDraft(for: value) }

                    Text("min")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        minutes.removeAll { $0 == value }
                        drafts.removeValue(forKey: value)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func commitDraft(for oldValue: Int) {
        guard let text = drafts[oldValue],
              let newValue = Int(text.trimmingCharacters(in: .whitespaces)),
              newValue >= 1, newValue <= 1_440
        else {
            drafts[oldValue] = String(oldValue)
            return
        }
        drafts.removeValue(forKey: oldValue)
        if newValue != oldValue, !minutes.contains(newValue) {
            if let idx = minutes.firstIndex(of: oldValue) {
                minutes[idx] = newValue
                minutes.sort()
            }
        } else if newValue == oldValue {
            // no change
        } else {
            drafts[oldValue] = String(oldValue)
        }
    }

    private func addEntry() {
        let existing = Set(minutes)
        let next = (1 ... 1_440).first { !existing.contains($0) } ?? 1
        minutes.append(next)
        minutes.sort()
    }
}

// MARK: - BatteryWidgetSettings

struct BatteryWidgetSettings: View {
    @State private var showPercentage: Bool
    @Bindable private var prefs = PreferencesModel.shared

    init() {
        _showPercentage = State(initialValue: BatterySettings.shared.showPercentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Show Percentage", isOn: $showPercentage)
                .onChange(of: showPercentage) { _, newValue in
                    BatterySettings.shared.showPercentage = newValue
                }

            Divider()

            ToastAlertSection(
                enabled: $prefs.notifyBatteryLow,
                threshold: $prefs.batteryThreshold,
                thresholdRange: 5 ... 50,
                thresholdLabel: "Threshold"
            )
        }
    }
}

// MARK: - IntervalSettings

struct IntervalSettings: View {
    let title: String
    @State private var interval: Double
    let onIntervalChange: (Double) -> Void

    init(title: String, interval: Double, onChange: @escaping (Double) -> Void) {
        self.title = title
        _interval = State(initialValue: interval)
        onIntervalChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Update Interval", selection: $interval) {
                Text("1 second").tag(1.0)
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: interval) { _, newValue in
                onIntervalChange(newValue)
            }
        }
    }
}

// MARK: - NetworkWidgetSettings

struct NetworkWidgetSettings: View {
    var body: some View {
        IntervalSettings(
            title: "Update Interval",
            interval: NetworkSettings.shared.updateInterval
        ) { newValue in
            NetworkSettings.shared.updateInterval = newValue
        }
    }
}

// MARK: - CPUGraphWidgetSettings

struct CPUGraphWidgetSettings: View {
    @Bindable private var prefs = PreferencesModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GraphWidgetSettingsContent(
                displayMode: CPUGraphSettings.shared.displayMode,
                thresholds: CPUGraphSettings.shared.thresholds,
                interval: CPUGraphSettings.shared.updateInterval,
                onModeChange: { CPUGraphSettings.shared.displayMode = $0 },
                onThresholdsChange: { CPUGraphSettings.shared.thresholds = $0 },
                onIntervalChange: { CPUGraphSettings.shared.updateInterval = $0 }
            )

            Divider()

            ToastAlertSection(
                enabled: $prefs.notifyCPUHigh,
                threshold: $prefs.cpuThreshold,
                thresholdRange: 50 ... 100,
                thresholdLabel: "Threshold",
                sustainedDuration: $prefs.cpuSustainedDuration
            )
        }
    }
}

// MARK: - MemoryGraphWidgetSettings

struct MemoryGraphWidgetSettings: View {
    @Bindable private var prefs = PreferencesModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GraphWidgetSettingsContent(
                displayMode: MemoryGraphSettings.shared.displayMode,
                thresholds: MemoryGraphSettings.shared.thresholds,
                interval: MemoryGraphSettings.shared.updateInterval,
                onModeChange: { MemoryGraphSettings.shared.displayMode = $0 },
                onThresholdsChange: { MemoryGraphSettings.shared.thresholds = $0 },
                onIntervalChange: { MemoryGraphSettings.shared.updateInterval = $0 }
            )

            Divider()

            ToastAlertSection(
                enabled: $prefs.notifyMemoryHigh,
                threshold: $prefs.memoryThreshold,
                thresholdRange: 50 ... 100,
                thresholdLabel: "Threshold",
                sustainedDuration: $prefs.memorySustainedDuration
            )
        }
    }
}

// MARK: - GraphWidgetSettingsContent

struct GraphWidgetSettingsContent: View {
    @State private var displayMode: GraphDisplayMode
    @State private var thresholds: [ThresholdEntry]
    private let initialInterval: Double

    let onModeChange: (GraphDisplayMode) -> Void
    let onThresholdsChange: ([ThresholdEntry]) -> Void
    let onIntervalChange: (Double) -> Void

    init(
        displayMode: GraphDisplayMode,
        thresholds: [ThresholdEntry],
        interval: Double,
        onModeChange: @escaping (GraphDisplayMode) -> Void,
        onThresholdsChange: @escaping ([ThresholdEntry]) -> Void,
        onIntervalChange: @escaping (Double) -> Void
    ) {
        _displayMode = State(initialValue: displayMode)
        _thresholds = State(initialValue: thresholds)
        initialInterval = interval
        self.onModeChange = onModeChange
        self.onThresholdsChange = onThresholdsChange
        self.onIntervalChange = onIntervalChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Display Mode", selection: $displayMode) {
                    ForEach(GraphDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: displayMode) { _, newValue in
                    onModeChange(newValue)
                }
            }

            Divider()

            IntervalSettings(
                title: "Update Interval",
                interval: initialInterval,
                onChange: onIntervalChange
            )

            Divider()

            ThresholdEditorSection(thresholds: $thresholds)
        }
        .onChange(of: thresholds) { _, newValue in
            onThresholdsChange(newValue)
        }
    }
}

// MARK: - ToastAlertSection

private struct ToastAlertSection: View {
    @Binding var enabled: Bool
    @Binding var threshold: Double
    let thresholdRange: ClosedRange<Double>
    let thresholdLabel: String
    var sustainedDuration: Binding<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Toast Alert")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Enable", isOn: $enabled)

            DoubleSliderRow(
                label: thresholdLabel,
                value: $threshold,
                range: thresholdRange,
                step: 1,
                unit: "%"
            )
            .disabled(!enabled)

            if let sustained = sustainedDuration {
                DoubleSliderRow(
                    label: "Sustained",
                    value: sustained,
                    range: 1 ... 60,
                    step: 1,
                    unit: "s"
                )
                .disabled(!enabled)
            }
        }
    }
}

// MARK: - ThresholdEditorSection

private struct ThresholdEditorSection: View {
    @Binding var thresholds: [ThresholdEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Threshold Colors")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    thresholds.append(ThresholdEntry(above: 0.50, hex: 0xFF9F0A))
                    thresholds.sort { $0.above < $1.above }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Text("Color applies when usage \u{2265} threshold")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            ForEach(thresholds) { entry in
                ThresholdRow(
                    entry: entry,
                    onUpdate: { updated in
                        if let idx = thresholds.firstIndex(where: { $0.id == entry.id }) {
                            thresholds[idx] = updated
                            thresholds.sort { $0.above < $1.above }
                        }
                    },
                    onDelete: {
                        thresholds.removeAll { $0.id == entry.id }
                    }
                )
            }
        }
    }
}

// MARK: - ThresholdRow

private struct ThresholdRow: View {
    @State private var percentage: Double
    @State private var selectedColor: Color
    let onUpdate: (ThresholdEntry) -> Void
    let onDelete: () -> Void

    init(entry: ThresholdEntry, onUpdate: @escaping (ThresholdEntry) -> Void, onDelete: @escaping () -> Void) {
        _percentage = State(initialValue: entry.above * 100)
        _selectedColor = State(initialValue: Color(hex: entry.hex))
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(Int(percentage))%")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 36, alignment: .trailing)

            Slider(value: $percentage, in: 0 ... 100, step: 5)
                .onChange(of: percentage) { _, _ in
                    syncToParent()
                }

            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24)
                .onChange(of: selectedColor) { _, _ in
                    syncToParent()
                }

            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func syncToParent() {
        onUpdate(ThresholdEntry(above: percentage / 100.0, hex: selectedColor.toHex()))
    }
}

// MARK: - Preview Helper

func previewRow(format: String) -> some View {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return HStack {
        Text("Preview:")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        Text(formatter.string(from: Date()))
            .font(.system(size: 12, design: .monospaced))
    }
    .padding(.top, 4)
}
