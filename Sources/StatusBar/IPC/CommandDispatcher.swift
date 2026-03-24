import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "IPC")

// MARK: - CommandDispatcher

/// Decodes incoming IPC requests, routes them to the appropriate handler,
/// and encodes responses. Bridges socket I/O into @MainActor territory.
@MainActor
final class CommandDispatcher {
    private let handlers: [String: any CommandHandling]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    /// Process raw request data and return encoded response data.
    func dispatch(requestData: Data) -> Data {
        let request: IPCRequest
        do {
            request = try decoder.decode(IPCRequest.self, from: requestData)
        } catch {
            logger.error("Failed to decode IPC request: \(error.localizedDescription)")
            let response = IPCResponse(
                requestID: "unknown",
                result: .failure(.internalError("Invalid request: \(error.localizedDescription)"))
            )
            return (try? encoder.encode(response)) ?? Data()
        }

        if request.version != ipcProtocolVersion {
            let response = IPCResponse(
                requestID: request.requestID,
                result: .failure(.versionMismatch(
                    serverVersion: ipcProtocolVersion,
                    clientVersion: request.version
                ))
            )
            return (try? encoder.encode(response)) ?? Data()
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
        return (try? encoder.encode(response)) ?? Data()
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
