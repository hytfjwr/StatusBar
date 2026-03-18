import StatusBarKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - WidgetsSection

struct WidgetsSection: View {
    let registry: WidgetRegistry
    @State private var settingsTarget: WidgetIDWrapper?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Widgets", resetAction: registry.resetLayout)

            SectionGroup(
                position: .left, icon: "sidebar.left", color: .blue,
                registry: registry, onOpenSettings: openSettings
            )
            SectionGroup(
                position: .center, icon: "align.horizontal.center", color: .purple,
                registry: registry, onOpenSettings: openSettings
            )
            SectionGroup(
                position: .right, icon: "sidebar.right", color: .orange,
                registry: registry, onOpenSettings: openSettings
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $settingsTarget) { wrapper in
            WidgetSettingsSheet(widgetID: wrapper.id)
        }
    }

    private func openSettings(for widgetID: String) {
        settingsTarget = WidgetIDWrapper(id: widgetID)
    }
}

// MARK: - WidgetIDWrapper

private struct WidgetIDWrapper: Identifiable {
    let id: String
}

// MARK: - SectionGroup

private struct SectionGroup: View {
    let position: WidgetPosition
    let icon: String
    let color: Color
    let registry: WidgetRegistry
    let onOpenSettings: (String) -> Void
    @State private var isTargeted = false

    private var entries: [WidgetLayoutEntry] {
        registry.entries(for: position)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)

                Text(position.displayTitle)
                    .font(.system(size: 12, weight: .semibold))

                Text("\(entries.filter(\.isVisible).count)/\(entries.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // Widget rows
            if entries.isEmpty {
                Text("Drop widgets here")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(entries) { entry in
                        WidgetRow(
                            entry: entry,
                            sectionColor: color,
                            displayName: registry.displayName(for: entry.id),
                            sfSymbolName: registry.sfSymbolName(for: entry.id),
                            onVisibilityChange: { registry.setVisible($0, for: entry.id) },
                            onSettings: registry.hasSettings(for: entry.id) ? { onOpenSettings(entry.id) } : nil
                        )
                        .draggable(entry.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                    .onMove { source, destination in
                        registry.reorder(in: position, from: source, to: destination)
                    }
                    .onInsert(of: [.utf8PlainText]) { index, providers in
                        handleDrop(providers: providers, at: index)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(entries.count) * 40 + 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? color : Color.clear, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: isTargeted ? 0 : 1)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let widgetID = items.first else {
                return false
            }
            guard !entries.contains(where: { $0.id == widgetID }) else {
                return false
            }
            registry.move(widgetID: widgetID, to: position)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private func handleDrop(providers: [NSItemProvider], at index: Int) {
        guard let provider = providers.first else {
            return
        }
        _ = provider.loadTransferable(type: String.self) { result in
            if case let .success(widgetID) = result {
                Task { @MainActor in
                    registry.insertWidget(widgetID, inSection: position, at: index)
                }
            }
        }
    }
}

// MARK: - WidgetRow

private struct WidgetRow: View {
    let entry: WidgetLayoutEntry
    let sectionColor: Color
    let displayName: String
    let sfSymbolName: String
    let onVisibilityChange: (Bool) -> Void
    let onSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Drag grip
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            // Widget icon
            Image(systemName: sfSymbolName)
                .font(.system(size: 12))
                .foregroundStyle(entry.isVisible ? sectionColor : Color.gray.opacity(0.3))
                .frame(width: 20)

            // Name
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(entry.isVisible ? .primary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Section badge (read-only indicator)
            Text(entry.section.shortLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.section.labelColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.section.labelColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            // Settings gear
            if let onSettings {
                Button {
                    onSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Visibility toggle
            Button {
                onVisibilityChange(!entry.isVisible)
            } label: {
                Image(systemName: entry.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isVisible ? .secondary : .tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            entry.isVisible ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

// MARK: - WidgetPosition Helpers

private extension WidgetPosition {
    var displayTitle: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        }
    }

    var shortLabel: String {
        switch self {
        case .left: "L"
        case .center: "C"
        case .right: "R"
        }
    }

    var sectionIcon: String {
        switch self {
        case .left: "sidebar.left"
        case .center: "align.horizontal.center"
        case .right: "sidebar.right"
        }
    }

    var labelColor: Color {
        switch self {
        case .left: .blue
        case .center: .purple
        case .right: .orange
        }
    }
}
