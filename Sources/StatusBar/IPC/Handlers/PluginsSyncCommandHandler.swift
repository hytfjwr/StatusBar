import StatusBarKit

@MainActor
struct PluginsSyncCommandHandler: CommandHandling {
    let commandKey = "pluginsSync"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .pluginsSync(frozen) = command else {
            throw IPCError.unknownCommand
        }
        // Sync is long-running (network + downloads). Run it in a detached task and
        // acknowledge immediately; surface the outcome through toast notifications.
        Task { @MainActor in
            do {
                let result = try await PluginsManager.shared.sync(frozen: frozen)
                postResultToast(result, frozen: frozen)
            } catch {
                ToastManager.shared.post(ToastRequest(
                    title: "Plugin sync failed",
                    message: error.localizedDescription,
                    icon: "xmark.circle",
                    level: .error,
                    duration: 6
                ))
            }
        }
        return .ok
    }

    @MainActor
    private func postResultToast(_ result: PluginsSyncResult, frozen: Bool) {
        let title = frozen ? "Plugin sync (frozen)" : "Plugin sync"
        ToastManager.shared.post(ToastRequest(
            title: title,
            message: result.summary,
            icon: result.hasErrors ? "exclamationmark.triangle" : "checkmark.circle",
            level: result.hasErrors ? .warning : .success,
            duration: result.hasErrors ? 8 : 4
        ))
    }
}
