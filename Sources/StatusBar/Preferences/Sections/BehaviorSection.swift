import ServiceManagement
import SwiftUI

struct BehaviorSection: View {
    @Bindable var model: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Behavior", resetAction: model.resetBehavior)

            GroupBox("Auto-Hide") {
                VStack(spacing: 10) {
                    ToggleRow(label: "Enable Auto-Hide", value: $model.autoHideEnabled)
                    DoubleSliderRow(
                        label: "Dwell Time",
                        value: $model.autoHideDwellTime,
                        range: 0.1...2.0,
                        step: 0.05,
                        unit: "s",
                        fractionDigits: 2
                    )
                    .disabled(!model.autoHideEnabled)
                    DoubleSliderRow(
                        label: "Fade Duration",
                        value: $model.autoHideFadeDuration,
                        range: 0.05...1.0,
                        step: 0.05,
                        unit: "s",
                        fractionDigits: 2
                    )
                    .disabled(!model.autoHideEnabled)
                }
                .padding(8)
            }

            GroupBox("Launch") {
                VStack(spacing: 10) {
                    ToggleRow(label: "Launch at Login", value: $model.launchAtLogin)
                        .onChange(of: model.launchAtLogin) { _, enabled in
                            LaunchAtLoginService.setEnabled(enabled)
                        }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - LaunchAtLoginService

enum LaunchAtLoginService {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SPM executables without a proper bundle may fail silently
        }
    }
}
