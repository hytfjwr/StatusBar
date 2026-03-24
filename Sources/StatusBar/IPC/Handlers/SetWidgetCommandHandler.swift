import StatusBarKit

@MainActor
struct SetWidgetCommandHandler: CommandHandling {
    let commandKey = "setWidget"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .setWidget(id, key, value) = command else {
            throw IPCError.unknownCommand
        }

        guard WidgetRegistry.shared.layout.contains(where: { $0.id == id }) else {
            throw IPCError.widgetNotFound(id: id)
        }

        // Handle visibility toggle via WidgetRegistry
        if key == "visible" {
            guard let visible = value.boolValue else {
                throw IPCError.invalidValue(key: "visible", reason: "expected boolean")
            }
            WidgetRegistry.shared.setVisible(visible, for: id)
            return .ok
        }

        // Handle widget-specific settings via WidgetConfigRegistry
        let configRegistry = WidgetConfigRegistry.shared
        let existing = configRegistry.exportAll()[id] ?? [:]

        // Merge the new key into existing settings
        var merged = existing
        merged[key] = value

        // Update only this widget's config, preserving all other widgets
        var allConfig = configRegistry.exportAll()
        allConfig[id] = merged
        configRegistry.setLoadedConfig(allConfig)
        configRegistry.applyToAll()
        configRegistry.notifySettingsChanged()
        return .ok
    }
}
