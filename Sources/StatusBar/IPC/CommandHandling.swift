import StatusBarKit

/// Protocol for IPC command handlers.
/// Each handler processes a specific `IPCCommand` case and returns a payload.
@MainActor
protocol CommandHandling {
    var commandKey: String { get }
    func handle(_ command: IPCCommand) throws -> IPCPayload
}
