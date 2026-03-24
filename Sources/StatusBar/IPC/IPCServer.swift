import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "IPCServer")

// MARK: - Accept Loop

/// Build and start the DispatchSource accept loop.
/// Must be a free function — closures formed inside a @MainActor context
/// inherit MainActor isolation, causing a Swift 6 runtime SIGTRAP when
/// GCD executes them on a background queue.
private func makeAcceptSource(
    fd: Int32,
    dispatcher: CommandDispatcher
) -> DispatchSourceRead {
    let source = DispatchSource.makeReadSource(
        fileDescriptor: fd,
        queue: DispatchQueue(label: "com.statusbar.ipc.accept", qos: .utility)
    )
    source.setEventHandler {
        let clientFD = accept(fd, nil, nil)
        guard clientFD >= 0 else {
            logger.debug("IPC accept returned invalid fd")
            return
        }
        logger.debug("IPC accepted client (fd=\(clientFD))")
        handleClient(fd: clientFD, dispatcher: dispatcher)
    }
    source.setCancelHandler {
        close(fd)
    }
    source.resume()
    return source
}

/// Handle a single IPC client connection on a detached task.
private func handleClient(fd: Int32, dispatcher: CommandDispatcher) {
    Task.detached {
        defer { close(fd) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let request: IPCRequest
        do {
            guard let req = try IPCFraming.readFrame(fd: fd, as: IPCRequest.self) else {
                logger.warning("IPC client disconnected before sending request")
                return
            }
            request = req
        } catch {
            logger.error("IPC failed to read request: \(error)")
            return
        }

        logger.debug("IPC received command: \(request.command.handlerKey)")

        let response = await MainActor.run {
            dispatcher.dispatch(request)
        }

        do {
            let frame = try IPCFraming.encode(response)
            if !IPCFraming.writeFrame(fd: fd, data: frame) {
                logger.error("IPC failed to write response frame")
            }
        } catch {
            logger.error("IPC failed to encode response: \(error)")
        }
    }
}

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

        acceptSource = makeAcceptSource(fd: serverFD, dispatcher: dispatcher)

        // swiftformat:disable:next redundantSelf
        logger.info("IPC server listening on \(self.socketPath)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        serverFD = -1
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
}
