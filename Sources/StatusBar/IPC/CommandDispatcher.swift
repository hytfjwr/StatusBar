import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "IPC")

// MARK: - CommandDispatcher

/// Routes incoming IPC requests to the appropriate handler and encodes responses.
@MainActor
final class CommandDispatcher {
    private let handlers: [String: any CommandHandling]
    private let encoder = JSONEncoder()

    init() {
        let all: [any CommandHandling] = [
            ListCommandHandler(),
            GetWidgetCommandHandler(),
            SetWidgetCommandHandler(),
            SetGlobalCommandHandler(),
            ReloadCommandHandler(),
        ]
        handlers = Dictionary(uniqueKeysWithValues: all.map { ($0.commandKey, $0) })
    }

    /// Process an IPC request and return the framed response (length-prefixed JSON).
    func dispatch(_ request: IPCRequest) -> Data {
        if request.version != ipcProtocolVersion {
            return encode(IPCResponse(
                requestID: request.requestID,
                result: .failure(.versionMismatch(
                    serverVersion: ipcProtocolVersion,
                    clientVersion: request.version
                ))
            ))
        }

        let result: IPCResult
        let handlerKey = request.command.handlerKey
        if let handler = handlers[handlerKey] {
            do {
                let payload = try handler.handle(request.command)
                result = .success(payload)
            } catch let error as IPCError {
                result = .failure(error)
            } catch {
                result = .failure(.internalError(error.localizedDescription))
            }
        } else {
            result = .failure(.unknownCommand)
        }

        let response = IPCResponse(requestID: request.requestID, result: result)
        logger.debug("IPC \(handlerKey) → \(String(describing: result))")
        return encode(response)
    }

    private func encode(_ response: IPCResponse) -> Data {
        (try? encoder.encode(response)) ?? Data()
    }
}

// MARK: - IPCCommand handler key mapping

extension IPCCommand {
    var handlerKey: String {
        switch self {
        case .list: "list"
        case .getWidget: "getWidget"
        case .setWidget: "setWidget"
        case .setGlobal: "setGlobal"
        case .reload: "reload"
        @unknown default: "unknown"
        }
    }
}
