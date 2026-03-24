import Foundation
import StatusBarIPC

// MARK: - IPCClient

/// Synchronous IPC client that connects to the StatusBar app via Unix domain socket.
enum IPCClient {
    /// Send a command and return the response payload.
    /// Throws `IPCClientError.appNotRunning` if the app is not running.
    static func send(_ command: IPCCommand) throws -> IPCPayload {
        let socketPath = ipcSocketPath()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCClientError.socketCreationFailed
        }
        defer { close(fd) }

        // Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            pathBytes.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else {
                    return
                }
                _ = memcpy(sunPath, base, buf.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED {
                throw IPCClientError.appNotRunning
            }
            throw IPCClientError.connectionFailed(String(cString: strerror(errno)))
        }

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

        // Check for protocol version mismatch
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
