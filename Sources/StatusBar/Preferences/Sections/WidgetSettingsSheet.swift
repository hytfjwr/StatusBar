import StatusBarKit
import SwiftUI

// MARK: - WidgetSettingsSheet

struct WidgetSettingsSheet: View {
    let widgetID: String
    @Environment(\.dismiss) private var dismiss

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
        .frame(width: 360, height: 240)
    }

    @ViewBuilder
    private var settingsContent: some View {
        WidgetRegistry.shared.settingsView(for: widgetID)
    }

    private var displayName: String {
        widgetID
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}


// MARK: - Time Widget Settings

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

// MARK: - Date Widget Settings

struct DateWidgetSettings: View {
    @State private var format: String

    init() {
        _format = State(initialValue: DateSettings.shared.format)
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
        }
    }
}

// MARK: - Battery Widget Settings

struct BatteryWidgetSettings: View {
    @State private var showPercentage: Bool

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
        }
    }
}

// MARK: - Interval Settings (shared pattern)

struct IntervalSettings: View {
    let title: String
    @State private var interval: Double
    let onIntervalChange: (Double) -> Void

    init(title: String, interval: Double, onChange: @escaping (Double) -> Void) {
        self.title = title
        self._interval = State(initialValue: interval)
        self.onIntervalChange = onChange
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

// MARK: - Network Widget Settings

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

// MARK: - CPU Graph Widget Settings

struct CPUGraphWidgetSettings: View {
    var body: some View {
        IntervalSettings(
            title: "Update Interval",
            interval: CPUGraphSettings.shared.updateInterval
        ) { newValue in
            CPUGraphSettings.shared.updateInterval = newValue
        }
    }
}

// MARK: - Memory Graph Widget Settings

struct MemoryGraphWidgetSettings: View {
    var body: some View {
        IntervalSettings(
            title: "Update Interval",
            interval: MemoryGraphSettings.shared.updateInterval
        ) { newValue in
            MemoryGraphSettings.shared.updateInterval = newValue
        }
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
