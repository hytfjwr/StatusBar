import Foundation
import StatusBarKit

@MainActor
struct TriggerCommandHandler: CommandHandling {
    let commandKey = "trigger"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .trigger(eventName, payload) = command else {
            throw IPCError.unknownCommand
        }

        guard !eventName.isEmpty else {
            throw IPCError.invalidValue(key: "event", reason: "must not be empty")
        }

        let event = PluginEvent(
            name: eventName,
            payload: payload,
            timestamp: Date(),
            sourcePlugin: nil
        )
        DylibPluginLoader.shared.eventRouter.route(event)

        return .ok
    }
}
