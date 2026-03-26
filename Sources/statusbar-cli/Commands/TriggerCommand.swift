import ArgumentParser
import StatusBarIPC

struct TriggerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trigger",
        abstract: "Send a custom event to plugin widgets"
    )

    @Argument(help: "Fully-qualified event name (e.g. com.example.myapp.deploy_finished)")
    var event: String

    @Option(name: .long, help: "Event payload (JSON or plain string)")
    var payload: String?

    func run() throws {
        let jsonPayload = payload.map { JSONValue.parse($0) }
        let result = try IPCClient.send(.trigger(event: event, payload: jsonPayload))
        guard case .ok = result else {
            throw ExitCode.failure
        }
        print("OK")
    }
}
