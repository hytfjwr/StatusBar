import StatusBarKit
import SwiftUI

struct PluginsSection: View {
    @State private var githubURL: String = ""
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var installSuccess: String?
    @State private var needsRestart = false

    var store: PluginStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Plugins") {}

            // Installed plugins
            GroupBox("Installed") {
                if store.plugins.isEmpty {
                    Text("No plugins installed.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.plugins, id: \.id) { plugin in
                            pluginRow(plugin)
                            if plugin.id != store.plugins.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            // Add plugin
            GroupBox("Add Plugin") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("GitHub URL (e.g. https://github.com/user/repo)", text: $githubURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)

                        Button(action: installPlugin) {
                            if isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Install")
                            }
                        }
                        .disabled(githubURL.isEmpty || isInstalling)
                    }

                    if let error = installError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    if let success = installSuccess {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Label(
                        "Plugins run with full app permissions. Only install from trusted sources.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Restart prompt
            if needsRestart {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Restart required for changes to take effect.")
                        .font(.callout)
                    Spacer()
                    Button("Restart Now") {
                        restartApp()
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Plugin load results
            let failedResults = DylibPluginLoader.shared.loadResults.filter { !$0.isSuccess }
            if !failedResults.isEmpty {
                GroupBox("Load Errors") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failedResults, id: \.manifest.id) { result in
                            Label {
                                Text("\(result.manifest.name): \(result.error?.localizedDescription ?? "Unknown error")")
                                    .font(.caption)
                            } icon: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Plugin Row

    @ViewBuilder
    private func pluginRow(_ plugin: InstalledPluginRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = plugin.githubURL {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.enabled },
                set: { newValue in
                    store.setEnabled(newValue, for: plugin.id)
                    togglePlugin(plugin, enabled: newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(role: .destructive) {
                uninstallPlugin(id: plugin.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func installPlugin() {
        guard !githubURL.isEmpty else { return }
        isInstalling = true
        installError = nil
        installSuccess = nil

        Task {
            do {
                let record = try await GitHubPluginInstaller.shared.install(from: githubURL)
                githubURL = ""

                // Try hot-loading the plugin immediately
                if hotLoadPlugin(record) {
                    installSuccess = "\(record.name) v\(record.version) installed and loaded."
                } else {
                    installSuccess = "\(record.name) v\(record.version) installed."
                    showRestartDialog(pluginName: record.name)
                }
            } catch {
                installError = error.localizedDescription
            }
            isInstalling = false
        }
    }

    /// Attempt to load the plugin without restart. Returns true on success.
    private func hotLoadPlugin(_ record: InstalledPluginRecord) -> Bool {
        let bundleURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar/plugins")
            .appendingPathComponent("\(record.bundleName).statusplugin")

        let registry = WidgetRegistry.shared
        let existingIDs = Set(registry.layout.map(\.id))

        do {
            try DylibPluginLoader.shared.load(bundleURL: bundleURL, into: registry)
            registry.finalizeRegistration()

            // Start only the newly added widgets
            let allWidgets = registry.leftWidgets + registry.centerWidgets + registry.rightWidgets
            for widget in allWidgets where !existingIDs.contains(widget.id) {
                widget.start()
            }
            return true
        } catch {
            print("[PluginsSection] Hot-load failed: \(error.localizedDescription)")
            return false
        }
    }

    private func showRestartDialog(pluginName: String) {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "\(pluginName) was installed but could not be loaded at runtime. Restart to activate the plugin."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            restartApp()
        }
    }

    private func togglePlugin(_ plugin: InstalledPluginRecord, enabled: Bool) {
        let loader = DylibPluginLoader.shared
        let registry = WidgetRegistry.shared

        if enabled {
            // If not loaded yet, load from disk
            if !loader.isLoaded(plugin.id) {
                let bundleURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/statusbar/plugins")
                    .appendingPathComponent("\(plugin.bundleName).statusplugin")
                do {
                    try loader.load(bundleURL: bundleURL, into: registry)
                    registry.finalizeRegistration()
                } catch {
                    print("[PluginsSection] Failed to load plugin: \(error.localizedDescription)")
                    needsRestart = true
                    return
                }
            }
            // Show and start widgets
            for widgetID in loader.widgetIDs(for: plugin.id) {
                registry.setVisible(true, for: widgetID)
                let allWidgets = registry.leftWidgets + registry.centerWidgets + registry.rightWidgets
                allWidgets.first { $0.id == widgetID }?.start()
            }
        } else {
            // Stop and hide widgets
            for widgetID in loader.widgetIDs(for: plugin.id) {
                let allWidgets = registry.leftWidgets + registry.centerWidgets + registry.rightWidgets
                allWidgets.first { $0.id == widgetID }?.stop()
                registry.setVisible(false, for: widgetID)
            }
        }
    }

    private func uninstallPlugin(id: String) {
        do {
            DylibPluginLoader.shared.markForRemoval(pluginID: id)
            try GitHubPluginInstaller.shared.uninstall(pluginID: id)
            needsRestart = true
        } catch {
            installError = "Failed to uninstall: \(error.localizedDescription)"
        }
    }

    private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath ?? "")
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
