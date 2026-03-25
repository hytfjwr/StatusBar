import Foundation
import StatusBarIPC

// MARK: - IPCSubscriber

/// Long-lived IPC client for event subscriptions.
/// Connects to the StatusBar app, sends a subscribe request,
/// then reads newline-delimited JSON events until the connection closes.
enum IPCSubscriber {
    /// Subscribe to the given events and print each one as a JSON line to stdout.
    /// Blocks until the server closes the connection or the process is interrupted.
    static func subscribe(to events: [BarEventName]) throws {
        let fd = try IPCConnection.connect()
        defer { close(fd) }

        // Send subscribe request (length-prefixed frame, same as normal commands).
        let request = IPCRequest(command: .subscribe(events: events))
        let frame = try IPCFraming.encode(request)
        guard IPCFraming.writeFrame(fd: fd, data: frame) else {
            throw IPCClientError.writeFailed
        }

        // Read the ACK response (length-prefixed frame).
        guard let response = try IPCFraming.readFrame(fd: fd, as: IPCResponse.self) else {
            throw IPCClientError.readFailed
        }
        switch response.result {
        case let .success(payload):
            guard case .subscribeAck = payload else {
                throw IPCClientError.readFailed
            }
        case let .failure(error):
            throw error
        @unknown default:
            throw IPCClientError.readFailed
        }

        // Stream NDJSON lines until EOF or error.
        var buffer = Data()
        let chunkSize = 4_096
        var chunk = Data(count: chunkSize)

        while true {
            let bytesRead = chunk.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else {
                    return -1
                }
                return read(fd, base, chunkSize)
            }
            if bytesRead <= 0 {
                break
            }

            buffer.append(chunk.prefix(bytesRead))

            // Process complete lines.
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex ..< newlineIndex]
                if let line = String(data: lineData, encoding: .utf8) {
                    print(line)
                    fflush(stdout)
                }
                buffer.removeSubrange(buffer.startIndex ... newlineIndex)
            }
        }
    }
}
