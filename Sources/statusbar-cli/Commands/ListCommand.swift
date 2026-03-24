import ArgumentParser
import StatusBarIPC

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all widgets"
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let payload = try IPCClient.send(.list)
        let formatter: OutputFormatter = options.json ? JSONFormatter() : TextFormatter()

        guard case let .widgetList(widgets) = payload else {
            throw ExitCode.failure
        }
        print(formatter.formatWidgetList(widgets))
    }
}
