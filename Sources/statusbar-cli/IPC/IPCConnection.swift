import Foundation
import StatusBarIPC

// MARK: - IPCConnection

/// Shared socket connection logic for both request-response and streaming clients.
enum IPCConnection {
    /// Create and connect a Unix domain socket to the StatusBar app.
    /// The caller is responsible for closing the returned fd.
    static func connect() throws -> Int32 {
        let socketPath = ipcSocketPath()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCClientError.socketCreationFailed
        }

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
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            close(fd)
            if errno == ENOENT || errno == ECONNREFUSED {
                throw IPCClientError.appNotRunning
            }
            throw IPCClientError.connectionFailed(String(cString: strerror(errno)))
        }

        return fd
    }
}
