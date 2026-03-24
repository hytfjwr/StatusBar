import StatusBarKit

@MainActor
struct ListCommandHandler: CommandHandling {
    let commandKey = "list"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        let registry = WidgetRegistry.shared
        let configRegistry = WidgetConfigRegistry.shared
        let allSettings = configRegistry.exportAll()

        let dtos = registry.layout.map { entry in
            WidgetInfoDTO(
                id: entry.id,
                displayName: WidgetRegistry.displayName(for: entry.id),
                position: entry.section,
                sortIndex: entry.sortIndex,
                isVisible: entry.isVisible,
                settings: allSettings[entry.id] ?? [:]
            )
        }
        return .widgetList(dtos)
    }
}
