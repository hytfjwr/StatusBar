import StatusBarKit
import SwiftUI

struct AboutSection: View {
    @State private var showingResetConfirm = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App info
            HStack(spacing: 16) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("StatusBar")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("A native macOS status bar replacement")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 8)

            GroupBox("Data") {
                VStack(spacing: 10) {
                    HStack {
                        Text("Settings Folder")
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        Button("Open in Finder") {
                            openSettingsFolder()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }

            GroupBox("Reset") {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset All Settings")
                                .font(.system(size: 13, weight: .medium))
                            Text("Restores all preferences, widget layout, and presets to defaults.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset All", role: .destructive) {
                            showingResetConfirm = true
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Reset All Settings?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                resetAllSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all preferences, widget layout, presets, and widget settings to their defaults. This action cannot be undone.")
        }
    }

    private func openSettingsFolder() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatusBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([appSupport])
    }

    private func resetAllSettings() {
        PreferencesModel.shared.resetAll()
        WidgetRegistry.shared.resetLayout()
        PresetStore.shared.deleteAllUserPresets()

        // Remove all per-widget settings (widget.* keys)
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("widget.") {
            defaults.removeObject(forKey: key)
        }
    }
}
