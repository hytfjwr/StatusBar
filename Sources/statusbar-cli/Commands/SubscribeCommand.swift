import ArgumentParser
import StatusBarIPC

struct SubscribeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscribe",
        abstract: "Subscribe to events and print JSON lines to stdout"
    )

    @Argument(help: "Events to subscribe to (\(BarEventName.allCases.map(\.rawValue).joined(separator: ", ")))")
    var events: [String]

    func run() throws {
        let names = try events.map { raw -> BarEventName in
            guard let name = BarEventName(rawValue: raw) else {
                throw ValidationError(
                    "Unknown event: '\(raw)'. Valid events: \(BarEventName.allCases.map(\.rawValue).joined(separator: ", "))"
                )
            }
            return name
        }

        guard !names.isEmpty else {
            throw ValidationError("At least one event name is required")
        }

        try IPCSubscriber.subscribe(to: names)
    }
}
