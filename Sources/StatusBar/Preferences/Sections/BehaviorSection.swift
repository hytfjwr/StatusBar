import ServiceManagement
import SwiftUI

// MARK: - BehaviorSection

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
                        range: 0.1 ... 2.0,
                        step: 0.05,
                        unit: "s",
                        fractionDigits: 2
                    )
                    .disabled(!model.autoHideEnabled)
                    DoubleSliderRow(
                        label: "Fade Duration",
                        value: $model.autoHideFadeDuration,
                        range: 0.05 ... 1.0,
                        step: 0.05,
                        unit: "s",
                        fractionDigits: 2
                    )
                    .disabled(!model.autoHideEnabled)
                }
                .padding(8)
            }

            GroupBox("Fullscreen") {
                VStack(spacing: 10) {
                    ToggleRow(label: "Hide in Fullscreen", value: $model.hideInFullscreen)
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
        // Only register with SMAppService when running as a proper .app bundle.
        // Development builds (.build/debug/StatusBar) should not register as login items.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SMAppService may fail for unsigned or ad-hoc signed bundles
        }
    }
}
