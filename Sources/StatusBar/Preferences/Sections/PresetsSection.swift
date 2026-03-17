import StatusBarKit
import SwiftUI
import UniformTypeIdentifiers

struct PresetsSection: View {
    private let store = PresetStore.shared
    @State private var selectedPresetID: UUID? = PresetStore.builtInPresets[0].id
    @State private var showingSaveAlert = false
    @State private var newPresetName = ""
    @State private var showingApplyConfirm = false
    @State private var pendingApply: Preset?
    @State private var showingImporter = false
    @State private var exportingData: Data?
    @State private var exportFilename = "preset.json"

    private var selectedPreset: Preset? {
        store.allPresets.first { $0.id == selectedPresetID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Presets")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Import…") { showingImporter = true }
                    .controlSize(.small)
            }
            .padding(.bottom, 8)

            // Two-panel layout
            HStack(alignment: .top, spacing: 12) {
                presetList
                    .frame(width: 220)
                presetDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Save Current State", isPresented: $showingSaveAlert) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                store.saveCurrentState(name: name)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Enter a name for this preset.")
        }
        .confirmationDialog(
            "Apply \"\(pendingApply?.name ?? "")\"?",
            isPresented: $showingApplyConfirm,
            titleVisibility: .visible
        ) {
            Button("Apply", role: .destructive) {
                if let p = pendingApply { store.apply(p) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace all current settings and widget layout.")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportingData != nil },
                set: { if !$0 { exportingData = nil } }
            ),
            document: exportingData.map { PresetDocument(data: $0) },
            contentType: .json,
            defaultFilename: exportFilename
        ) { _ in
            exportingData = nil
        }
    }

    // MARK: - Preset List

    @ViewBuilder
    private var presetList: some View {
        VStack(spacing: 0) {
            List(store.allPresets, selection: $selectedPresetID) { preset in
                PresetListRow(preset: preset)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            Button {
                newPresetName = ""
                showingSaveAlert = true
            } label: {
                Label("Save Current State", systemImage: "plus")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
    }

    // MARK: - Preset Detail

    @ViewBuilder
    private var presetDetail: some View {
        if let preset = selectedPreset {
            VStack(alignment: .leading, spacing: 12) {
                // Name + badge
                HStack(spacing: 8) {
                    Text(preset.name)
                        .font(.headline)
                    if preset.isBuiltIn {
                        Text("Built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if !preset.isBuiltIn {
                    Text(preset.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Color preview
                SnapshotPreview(snapshot: preset.snapshot)

                Divider()

                // Actions
                VStack(spacing: 8) {
                    Button {
                        pendingApply = preset
                        showingApplyConfirm = true
                    } label: {
                        Text("Apply Preset")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        if let data = store.exportData(preset) {
                            exportFilename = "\(preset.name).json"
                            exportingData = data
                        }
                    } label: {
                        Text("Export…")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)

                    if !preset.isBuiltIn {
                        Button(role: .destructive) {
                            store.delete(preset)
                            selectedPresetID = PresetStore.builtInPresets[0].id
                        } label: {
                            Text("Delete")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.regular)
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
        } else {
            VStack {
                Spacer()
                Text("Select a preset")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Import Helper

    private func handleImport(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        _ = store.importPreset(from: data)
    }
}

// MARK: - PresetListRow

private struct PresetListRow: View {
    let preset: Preset

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: preset.isBuiltIn ? "square.on.square.dashed" : "person")
                .font(.system(size: 10))
                .foregroundStyle(preset.isBuiltIn ? Color.secondary : Color.blue)
                .frame(width: 14)
            Text(preset.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
    }
}

// MARK: - SnapshotPreview

private struct SnapshotPreview: View {
    let snapshot: PresetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Simulated bar
            RoundedRectangle(cornerRadius: CGFloat(snapshot.barCornerRadius) / 3)
                .fill(Color(hex: snapshot.barTintHex).opacity(max(0.08, snapshot.barTintOpacity)))
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(snapshot.barCornerRadius) / 3)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(snapshot.barHeight) * 0.6)

            // Color palette
            HStack(spacing: 4) {
                colorSwatch(snapshot.accentHex)
                colorSwatch(snapshot.greenHex)
                colorSwatch(snapshot.yellowHex)
                colorSwatch(snapshot.redHex)
                colorSwatch(snapshot.cyanHex)
                colorSwatch(snapshot.purpleHex)
            }

            // Graph colors
            HStack(spacing: 4) {
                colorSwatch(snapshot.cpuGraphHex)
                colorSwatch(snapshot.memoryGraphHex)
                Text("CPU / Memory")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Dimensions summary
            Text("Bar: \(Int(snapshot.barHeight))px, Radius: \(Int(snapshot.barCornerRadius))px, Font: \(Int(snapshot.labelFontSize))px")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func colorSwatch(_ hex: UInt32) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex))
            .frame(width: 20, height: 20)
    }
}

// MARK: - PresetDocument (for fileExporter)

struct PresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
