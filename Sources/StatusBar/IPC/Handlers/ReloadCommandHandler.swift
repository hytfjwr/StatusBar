import StatusBarKit

@MainActor
struct ReloadCommandHandler: CommandHandling {
    let commandKey = "reload"

    func handle(_ command: IPCCommand) async throws -> IPCPayload {
        AppUpdateService.relaunchApp()
        return .ok
    }
}
