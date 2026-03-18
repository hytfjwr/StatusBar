import AppKit
import StatusBarKit
import SwiftUI

struct AboutSection: View {
    @State private var showingResetConfirm = false
    private let updateService = AppUpdateService.shared

    private var appVersion: String {
        AppUpdateService.appVersion
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

            GroupBox("Updates") {
                VStack(spacing: 10) {
                    HStack {
                        updateStatusView
                        Spacer()
                        Button {
                            Task { await updateService.checkForUpdates() }
                        } label: {
                            if case .checking = updateService.state {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Check for Updates")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isChecking)
                    }
                }
                .padding(8)
            }

            GroupBox("Help") {
                VStack(spacing: 10) {
                    HStack {
                        Text("Welcome Guide")
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        Button("Show Welcome") {
                            OnboardingWindow.shared.show()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }

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
            Text(
                "This will reset all preferences, widget layout, presets, and widget settings to their defaults."
                    + " This action cannot be undone."
            )
        }
    }

    private func openSettingsFolder() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([configDir])
    }

    private var isChecking: Bool {
        if case .checking = updateService.state {
            return true
        }
        return false
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateService.state {
        case .idle:
            Text("Not checked yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .checking:
            Text("Checking...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case let .available(version, url):
            HStack(spacing: 6) {
                Label("v\(version) available", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                Button("Download") {
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
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
