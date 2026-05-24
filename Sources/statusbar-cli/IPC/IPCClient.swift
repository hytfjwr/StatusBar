import Foundation
import StatusBarIPC

// MARK: - IPCClient

/// Synchronous IPC client for request-response commands.
enum IPCClient {
    /// Send a command and return the response payload.
    /// Throws `IPCClientError.appNotRunning` if the app is not running.
    static func send(_ command: IPCCommand) throws -> IPCPayload {
        let fd = try IPCConnection.connect()
        defer { close(fd) }

        // Send request
        let request = IPCRequest(command: command)
        let frame = try IPCFraming.encode(request)
        guard IPCFraming.writeFrame(fd: fd, data: frame) else {
            throw IPCClientError.writeFailed
        }

        // Read response
        guard let response = try IPCFraming.readFrame(fd: fd, as: IPCResponse.self) else {
            throw IPCClientError.readFailed
        }

        switch response.result {
        case let .success(payload):
            return payload
        case let .failure(error):
            throw error
        @unknown default:
            throw IPCClientError.readFailed
        }
    }
}

// MARK: - IPCClientError

enum IPCClientError: Error, CustomStringConvertible {
    case appNotRunning
    case socketCreationFailed
    case connectionFailed(String)
    case writeFailed
    case readFailed

    var description: String {
        switch self {
        case .appNotRunning:
            "StatusBar is not running"
        case .socketCreationFailed:
            "Failed to create socket"
        case let .connectionFailed(reason):
            "Connection failed: \(reason)"
        case .writeFailed:
            "Failed to send request"
        case .readFailed:
            "Failed to read response"
        }
    }
}

// MARK: - IPCError + @retroactive CustomStringConvertible

/// Default debug rendering for `IPCError` (defined in the external StatusBarKit package) is
/// Swift's enum-with-associated-value form — `internalError("...")` — which leaks the case name
/// to end users. Render it as the underlying message so ArgumentParser's "Error: ..." line is
/// readable.
extension IPCError: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknownCommand:
            "Unknown command"
        case let .widgetNotFound(id):
            "Widget not found: \(id)"
        case let .invalidKeyPath(path):
            "Invalid key path: \(path)"
        case let .invalidValue(key, reason):
            "Invalid value for \(key): \(reason)"
        case let .versionMismatch(server, client):
            "IPC protocol mismatch (server v\(server), client v\(client)) — reinstall sbar"
        case let .internalError(message):
            message
        @unknown default:
            "Unknown IPC error"
        }
    }
}
