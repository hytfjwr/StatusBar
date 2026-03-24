import StatusBarKit

@MainActor
struct GetWidgetCommandHandler: CommandHandling {
    let commandKey = "getWidget"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .getWidget(id) = command else {
            throw IPCError.unknownCommand
        }

        let registry = WidgetRegistry.shared
        guard let entry = registry.layout.first(where: { $0.id == id }) else {
            throw IPCError.widgetNotFound(id: id)
        }

        let settings = WidgetConfigRegistry.shared.exportAll()[id] ?? [:]
        let dto = WidgetInfoDTO(
            id: entry.id,
            displayName: WidgetRegistry.displayName(for: entry.id),
            position: entry.section,
            sortIndex: entry.sortIndex,
            isVisible: entry.isVisible,
            settings: settings
        )
        return .widgetDetail(dto)
    }
}
