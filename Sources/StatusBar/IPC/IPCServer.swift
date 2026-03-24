import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "IPCServer")

// MARK: - IPCServer

/// Unix domain socket server for IPC.
/// Listens on `~/.config/statusbar/statusbar.sock` and dispatches incoming
/// requests to `CommandDispatcher` on the main actor.
@MainActor
final class IPCServer {
    static let shared = IPCServer()

    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let dispatcher = CommandDispatcher()
    private let socketPath = ipcSocketPath()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            logger.error("Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        guard bindSocket() else {
            close(serverFD)
            serverFD = -1
            return
        }

        chmod(socketPath, 0o600)

        guard Darwin.listen(serverFD, 5) == 0 else {
            logger.error("Failed to listen: \(String(cString: strerror(errno)))")
            close(serverFD)
            serverFD = -1
            return
        }

        startAcceptLoop()

        // swiftformat:disable:next redundantSelf
        logger.info("IPC server listening on \(self.socketPath)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(socketPath)
        logger.info("IPC server stopped")
    }

    // MARK: - Socket setup

    private func bindSocket() -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            // swiftformat:disable:next redundantSelf
            logger.error("Socket path too long: \(self.socketPath)")
            return false
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            pathBytes.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else {
                    return
                }
                _ = memcpy(sunPath, base, buf.count)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            logger.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            return false
        }
        return true
    }

    private func startAcceptLoop() {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: serverFD,
            queue: DispatchQueue(label: "com.statusbar.ipc.accept", qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                return
            }
            handleClientAsync(fd: clientFD)
        }
        source.setCancelHandler { [weak self] in
            guard let self else {
                return
            }
            if serverFD >= 0 {
                close(serverFD)
                serverFD = -1
            }
        }
        source.resume()
        acceptSource = source
    }

    // MARK: - Client handling

    nonisolated private func handleClientAsync(fd: Int32) {
        Task.detached {
            defer { close(fd) }

            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            guard let request = try? IPCFraming.readFrame(fd: fd, as: IPCRequest.self) else {
                logger.debug("IPC client disconnected or sent invalid frame")
                return
            }

            let responseJSON = await MainActor.run {
                self.dispatcher.dispatch(request)
            }

            var length = UInt32(responseJSON.count).bigEndian
            var frame = Data(bytes: &length, count: 4)
            frame.append(responseJSON)
            _ = IPCFraming.writeFrame(fd: fd, data: frame)
        }
    }
}
