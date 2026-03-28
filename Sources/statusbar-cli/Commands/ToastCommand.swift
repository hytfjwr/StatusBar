import ArgumentParser
import StatusBarIPC

// MARK: - ToastLevel + ExpressibleByArgument

extension ToastLevel: ExpressibleByArgument {}

// MARK: - ToastCommand

struct ToastCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toast",
        abstract: "Show a toast notification on the status bar"
    )

    @Option(name: .long, help: "Toast title (required)")
    var title: String

    @Option(name: .long, help: "Toast message body")
    var message: String?

    @Option(name: .long, help: "SF Symbol name (e.g. exclamationmark.triangle)")
    var icon: String?

    @Option(name: .long, help: "Severity level: info, success, warning, error (default: info)")
    var level: ToastLevel = .info

    @Option(name: .long, help: "Auto-dismiss duration in seconds (default: 5, 0 = persistent)")
    var duration: Double = 5.0

    @Option(name: .customLong("action-label"), help: "Label for the action button")
    var actionLabel: String?

    @Option(name: .long, help: "Shell command to run when action button is clicked")
    var action: String?

    func run() throws {
        let request = ToastRequest(
            title: title,
            message: message,
            icon: icon,
            level: level,
            duration: duration,
            actionLabel: actionLabel,
            actionShellCommand: action
        )
        let payload = try IPCClient.send(.showToast(request: request))
        guard case let .toastID(id) = payload else {
            throw ExitCode.failure
        }
        print(id)
    }
}
