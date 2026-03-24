import StatusBarKit

@MainActor
struct ReloadCommandHandler: CommandHandling {
    let commandKey = "reload"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        ConfigLoader.shared.reloadFromDisk()
        return .ok
    }
}
