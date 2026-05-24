import StatusBarKit

@MainActor
struct PluginsListCommandHandler: CommandHandling {
    let commandKey = "pluginsList"

    func handle(_ command: IPCCommand) async throws -> IPCPayload {
        guard case .pluginsList = command else {
            throw IPCError.unknownCommand
        }
        return .pluginList(PluginsManager.shared.manifestEntryDTOs())
    }
}
