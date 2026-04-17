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

        if key == "visible" {
            guard let visible = value.boolValue else {
                throw IPCError.invalidValue(key: "visible", reason: "expected boolean")
            }
            WidgetRegistry.shared.setVisible(visible, for: id)
            return .ok
        }

        // Read-only runtime state exposed by `get widget`; never persisted.
        if key.hasPrefix("state.") {
            throw IPCError.invalidValue(key: key, reason: "state.* keys are read-only runtime fields")
        }

        let configRegistry = WidgetConfigRegistry.shared
        var allConfig = configRegistry.exportAll()
        var widgetConfig = allConfig[id] ?? [:]
        widgetConfig[key] = value
        allConfig[id] = widgetConfig
        configRegistry.setLoadedConfig(allConfig)
        configRegistry.applyToAll()
        configRegistry.notifySettingsChanged()
        return .ok
    }
}
