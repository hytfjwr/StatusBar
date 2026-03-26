import ArgumentParser

// MARK: - SbarCLI

@main
struct SbarCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sbar",
        abstract: "Control the StatusBar app from the command line",
        subcommands: [
            ListCommand.self,
            GetCommand.self,
            SetCommand.self,
            ReloadCommand.self,
            SubscribeCommand.self,
            TriggerCommand.self,
        ]
    )
}

// MARK: - GlobalOptions

/// Shared options available to all subcommands.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
}
