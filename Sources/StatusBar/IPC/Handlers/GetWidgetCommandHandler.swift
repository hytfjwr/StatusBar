import StatusBarKit

@MainActor
struct GetWidgetCommandHandler: CommandHandling {
    let commandKey = "getWidget"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .getWidget(id) = command else {
            throw IPCError.unknownCommand
        }

        guard let entry = WidgetRegistry.shared.layout.first(where: { $0.id == id }) else {
            throw IPCError.widgetNotFound(id: id)
        }

        let settings = WidgetConfigRegistry.shared.exportAll()[id] ?? [:]
        return .widgetDetail(.make(from: entry, settings: settings))
    }
}
