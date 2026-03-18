import SwiftUI

struct NotificationsSection: View {
    @Bindable var model: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Notifications", resetAction: model.resetNotifications)

            GroupBox("Permission") {
                VStack(spacing: 10) {
                    if NotificationService.shared.isAvailable {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications require system permission.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("Status: \(NotificationService.shared.permissionStatus)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Request Permission") {
                                NotificationService.shared.requestPermission()
                            }
                            .controlSize(.small)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.yellow)
                            Text(
                                "Notifications are unavailable in debug builds without a bundle identifier."
                                    + " Build as a .app bundle to enable."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
            }
            .onAppear {
                NotificationService.shared.refreshPermissionStatus()
            }

            GroupBox("Battery") {
                VStack(spacing: 10) {
                    ToggleRow(label: "Low Battery Alert", value: $model.notifyBatteryLow)
                    DoubleSliderRow(
                        label: "Threshold",
                        value: $model.batteryThreshold,
                        range: 5 ... 50,
                        step: 1,
                        unit: "%"
                    )
                    .disabled(!model.notifyBatteryLow)
                }
                .padding(8)
            }

            GroupBox("CPU") {
                VStack(spacing: 10) {
                    ToggleRow(label: "High CPU Alert", value: $model.notifyCPUHigh)
                    DoubleSliderRow(
                        label: "Threshold",
                        value: $model.cpuThreshold,
                        range: 50 ... 100,
                        step: 1,
                        unit: "%"
                    )
                    .disabled(!model.notifyCPUHigh)
                    DoubleSliderRow(
                        label: "Sustained",
                        value: $model.cpuSustainedDuration,
                        range: 1 ... 60,
                        step: 1,
                        unit: "s"
                    )
                    .disabled(!model.notifyCPUHigh)
                }
                .padding(8)
            }

            GroupBox("Memory") {
                VStack(spacing: 10) {
                    ToggleRow(label: "High Memory Alert", value: $model.notifyMemoryHigh)
                    DoubleSliderRow(
                        label: "Threshold",
                        value: $model.memoryThreshold,
                        range: 50 ... 100,
                        step: 1,
                        unit: "%"
                    )
                    .disabled(!model.notifyMemoryHigh)
                    DoubleSliderRow(
                        label: "Sustained",
                        value: $model.memorySustainedDuration,
                        range: 1 ... 60,
                        step: 1,
                        unit: "s"
                    )
                    .disabled(!model.notifyMemoryHigh)
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
