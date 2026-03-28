import StatusBarKit

@MainActor
struct ToastCommandHandler: CommandHandling {
    let commandKey = "showToast"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .showToast(request) = command else {
            throw IPCError.unknownCommand
        }
        let id = ToastManager.shared.post(request)
        return .toastID(id)
    }
}
