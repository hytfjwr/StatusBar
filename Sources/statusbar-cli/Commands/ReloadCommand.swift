import ArgumentParser
import StatusBarIPC

struct ReloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Relaunch the app"
    )

    func run() throws {
        let payload = try IPCClient.send(.reload)
        guard case .ok = payload else {
            throw ExitCode.failure
        }
        print("OK")
    }
}
