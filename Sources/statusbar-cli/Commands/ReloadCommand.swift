import ArgumentParser
import StatusBarIPC

struct ReloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Relaunch the app"
    )

    func run() throws {
        do {
            let payload = try IPCClient.send(.reload)
            guard case .ok = payload else {
                throw ExitCode.failure
            }
        } catch IPCClientError.readFailed {
            // Expected: the app terminates before sending a response.
        }
        print("OK")
    }
}
