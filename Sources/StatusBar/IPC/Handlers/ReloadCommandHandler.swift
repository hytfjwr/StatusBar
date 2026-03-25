import StatusBarKit

@MainActor
struct ReloadCommandHandler: CommandHandling {
    let commandKey = "reload"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        AppUpdateService.relaunchApp()
        return .ok
    }
}
