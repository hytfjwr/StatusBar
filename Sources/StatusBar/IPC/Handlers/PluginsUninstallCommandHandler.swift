import StatusBarKit

@MainActor
struct PluginsUninstallCommandHandler: CommandHandling {
    let commandKey = "pluginsUninstall"

    func handle(_ command: IPCCommand) async throws -> IPCPayload {
        guard case let .pluginsUninstall(source) = command else {
            throw IPCError.unknownCommand
        }
        do {
            try await PluginsManager.shared.remove(source: source)
        } catch {
            throw IPCError.internalError(error.localizedDescription)
        }
        return .ok
    }
}
