import ArgumentParser
import StatusBarIPC

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get widget details"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Widget ID (e.g. battery, cpu-graph)")
    var widget: String

    func run() throws {
        let payload = try IPCClient.send(.getWidget(id: widget))
        let formatter: OutputFormatter = options.json ? JSONFormatter() : TextFormatter()

        guard case let .widgetDetail(info) = payload else {
            throw ExitCode.failure
        }
        print(formatter.formatWidgetDetail(info))
    }
}
