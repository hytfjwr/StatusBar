import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class WidgetRegistry: WidgetRegistryProtocol {
    static let shared = WidgetRegistry()

    /// Called after layout is persisted. Used to decouple from PreferencesModel.
    var onLayoutDidChange: (@MainActor () -> Void)?

    // All widget instances keyed by id (type-erased)
    private var allWidgets: [String: AnyStatusBarWidget] = [:]

    // Observable layout — drives BarContentView
    private(set) var layout: [WidgetLayoutEntry] = []

    // Default layout captured during registration, used by resetLayout()
    private var defaultLayout: [WidgetLayoutEntry] = []

    // Retain plugin instances to prevent deallocation after registration
    private var plugins: [any StatusBarPlugin] = []

    private let store = WidgetLayoutStore()
    private var registrationOrder = 0

    private init() {
        layout = store.load()
    }

    // MARK: - Registration

    func register(_ widget: some StatusBarWidget) {
        registerImpl(AnyStatusBarWidget(widget))
    }

    func register(_ widget: any StatusBarWidget) {
        func open<W: StatusBarWidget>(_ w: W) { registerImpl(AnyStatusBarWidget(w)) }
        open(widget)
    }

    private func registerImpl(_ erased: AnyStatusBarWidget) {
        allWidgets[erased.id] = erased

        if !layout.contains(where: { $0.id == erased.id }) {
            let entry = WidgetLayoutEntry(
                id: erased.id,
                section: erased.position,
                sortIndex: registrationOrder
            )
            layout.append(entry)
        }

        if !defaultLayout.contains(where: { $0.id == erased.id }) {
            defaultLayout.append(WidgetLayoutEntry(
                id: erased.id,
                section: erased.position,
                sortIndex: registrationOrder
            ))
        }

        registrationOrder += 1
    }

    func registerPlugin(_ plugin: any StatusBarPlugin) {
        plugins.append(plugin)
        plugin.register(to: self)
    }

    /// Remove orphaned entries and persist after all widgets are registered.
    func finalizeRegistration() {
        let knownIDs = Set(allWidgets.keys)
        layout.removeAll { !knownIDs.contains($0.id) }
        store.save(layout)
    }

    // MARK: - Lifecycle

    func startAll() {
        for widget in allWidgets.values {
            widget.start()
        }
    }

    func stopAll() {
        for widget in allWidgets.values {
            widget.stop()
        }
    }

    // MARK: - Ordered Widgets (consumed by BarContentView)

    var leftWidgets: [AnyStatusBarWidget] {
        widgets(forSection: .left)
    }

    var centerWidgets: [AnyStatusBarWidget] {
        widgets(forSection: .center)
    }

    var rightWidgets: [AnyStatusBarWidget] {
        widgets(forSection: .right)
    }

    // MARK: - WidgetRegistryProtocol

    func widgets(for position: WidgetPosition) -> [AnyStatusBarWidget] {
        widgets(forSection: position)
    }

    private func widgets(forSection section: WidgetPosition) -> [AnyStatusBarWidget] {
        layout
            .filter { $0.section == section && $0.isVisible }
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { allWidgets[$0.id] }
    }

    // MARK: - Mutation API (called by Preferences UI)

    func reorder(in section: WidgetPosition, from source: IndexSet, to destination: Int) {
        var sectionEntries = layout
            .filter { $0.section == section }
            .sorted { $0.sortIndex < $1.sortIndex }

        sectionEntries.move(fromOffsets: source, toOffset: destination)

        // Re-assign sortIndex within the section
        for (index, entry) in sectionEntries.enumerated() {
            if let layoutIndex = layout.firstIndex(where: { $0.id == entry.id }) {
                layout[layoutIndex].sortIndex = index
            }
        }

        persist()
    }

    func move(widgetID: String, to newSection: WidgetPosition) {
        guard let index = layout.firstIndex(where: { $0.id == widgetID }) else { return }
        let oldSection = layout[index].section

        // Append at the end of the new section
        let maxIndex = layout
            .filter { $0.section == newSection }
            .map(\.sortIndex)
            .max() ?? -1

        layout[index].section = newSection
        layout[index].sortIndex = maxIndex + 1

        // Re-number both sections
        renumber(section: oldSection)
        renumber(section: newSection)
        persist()
    }

    func insertWidget(_ widgetID: String, inSection section: WidgetPosition, at insertIndex: Int) {
        guard let layoutIndex = layout.firstIndex(where: { $0.id == widgetID }) else { return }
        let oldSection = layout[layoutIndex].section

        // Get current entries in the target section, sorted
        var sectionEntries = layout
            .filter { $0.section == section }
            .sorted { $0.sortIndex < $1.sortIndex }

        // Remove from old section entries if same section (reorder case)
        if oldSection == section {
            sectionEntries.removeAll { $0.id == widgetID }
        }

        // Move widget to new section
        layout[layoutIndex].section = section

        // Insert at the target position
        let clampedIndex = min(insertIndex, sectionEntries.count)
        sectionEntries.insert(layout[layoutIndex], at: clampedIndex)

        // Renumber the target section
        for (i, entry) in sectionEntries.enumerated() {
            if let idx = layout.firstIndex(where: { $0.id == entry.id }) {
                layout[idx].sortIndex = i
            }
        }

        // Renumber old section if cross-section move
        if oldSection != section {
            renumber(section: oldSection)
        }

        persist()
    }

    func setVisible(_ visible: Bool, for widgetID: String) {
        guard let index = layout.firstIndex(where: { $0.id == widgetID }) else { return }
        layout[index].isVisible = visible
        persist()
    }

    func resetLayout() {
        layout = defaultLayout
        persist()
    }

    func applyLayout(_ entries: [WidgetLayoutEntry]) {
        let knownIDs = Set(allWidgets.keys)
        // Keep only entries for widgets that actually exist
        var newLayout = entries.filter { knownIDs.contains($0.id) }
        // Append any registered widgets not in the preset (preserving defaultLayout order)
        let coveredIDs = Set(newLayout.map(\.id))
        let nextIndex = (newLayout.map(\.sortIndex).max() ?? -1) + 1
        let missingEntries = defaultLayout.filter { coveredIDs.contains($0.id) == false }
        for (offset, fallback) in missingEntries.enumerated() {
            var entry = fallback
            entry.sortIndex = nextIndex + offset
            newLayout.append(entry)
        }
        layout = newLayout
        persist()
    }

    // MARK: - Layout Queries for Preferences UI

    func entries(for section: WidgetPosition) -> [WidgetLayoutEntry] {
        layout
            .filter { $0.section == section }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func displayName(for widgetID: String) -> String {
        widgetID
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func sfSymbolName(for widgetID: String) -> String {
        allWidgets[widgetID]?.sfSymbolName ?? "square.dashed"
    }

    func hasSettings(for widgetID: String) -> Bool {
        allWidgets[widgetID]?.hasSettings ?? false
    }

    func settingsView(for widgetID: String) -> AnyView {
        allWidgets[widgetID]?.settingsBody() ?? AnyView(EmptyView())
    }

    // MARK: - Private

    private func renumber(section: WidgetPosition) {
        let sorted = layout
            .enumerated()
            .filter { $0.element.section == section }
            .sorted { $0.element.sortIndex < $1.element.sortIndex }

        for (newIndex, pair) in sorted.enumerated() {
            layout[pair.offset].sortIndex = newIndex
        }
    }

    private func persist() {
        store.save(layout)
        onLayoutDidChange?()
    }
}
