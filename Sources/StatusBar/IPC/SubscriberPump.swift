import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "SubscriberPump")

/// Run a long-lived subscriber pump that reads events from `EventBus` and
/// writes newline-delimited JSON to the client fd.
///
/// This function takes ownership of `fd` — it will be closed on return.
/// Must be called from a detached (non-MainActor) context.
func runSubscriberPump(fd: Int32, events: [BarEventName]) async {
    let (id, stream) = await MainActor.run {
        EventBus.shared.subscribe(to: events)
    }

    logger.info("Subscriber pump started (fd=\(fd), events=\(events.map(\.rawValue)))")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    for await envelope in stream {
        guard writeEventLine(fd: fd, envelope: envelope, encoder: encoder) else {
            logger.debug("Subscriber pump write failed (fd=\(fd)), stopping")
            break
        }
    }

    logger.info("Subscriber pump ended (fd=\(fd))")

    await MainActor.run { EventBus.shared.cancel(id: id) }
    close(fd)
}

/// Encode an event envelope as a single JSON line and write it to the fd.
private func writeEventLine(fd: Int32, envelope: IPCEventEnvelope, encoder: JSONEncoder) -> Bool {
    guard let json = try? encoder.encode(envelope) else {
        return false
    }
    var line = json
    line.append(0x0A)
    return IPCFraming.writeAll(fd: fd, data: line)
}
