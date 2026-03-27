import ArgumentParser
import StatusBarIPC

struct SubscribeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscribe",
        abstract: "Subscribe to events and print JSON lines to stdout"
    )

    @Argument(help: "Events to subscribe to (e.g. front_app_switched, volume_changed, config_reloaded)")
    var events: [String]

    func run() throws {
        guard !events.isEmpty else {
            throw ValidationError("At least one event name is required")
        }

        try IPCSubscriber.subscribe(to: events)
    }
}
