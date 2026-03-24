import StatusBarKit

@MainActor
struct ListCommandHandler: CommandHandling {
    let commandKey = "list"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        let allSettings = WidgetConfigRegistry.shared.exportAll()
        let dtos = WidgetRegistry.shared.layout.map { entry in
            WidgetInfoDTO.make(from: entry, settings: allSettings[entry.id] ?? [:])
        }
        return .widgetList(dtos)
    }
}
