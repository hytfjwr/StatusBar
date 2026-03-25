import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "EventBus")

// MARK: - EventBus

/// Pub/sub hub for IPC event subscriptions.
/// Producers call `emit(_:)` on the main actor; each subscriber receives
/// events through an `AsyncStream` filtered by their subscribed event names.
@MainActor
final class EventBus {
    static let shared = EventBus()

    private var subscriptions: [UUID: Subscription] = [:]

    private struct Subscription {
        let events: Set<BarEventName>
        let continuation: AsyncStream<IPCEventEnvelope>.Continuation
    }

    private init() {}

    /// Create a new subscription that yields events matching `events`.
    /// Returns a unique ID (for cancellation) and the stream to consume.
    func subscribe(to events: [BarEventName]) -> (id: UUID, stream: AsyncStream<IPCEventEnvelope>) {
        let id = UUID()
        let stream = AsyncStream<IPCEventEnvelope>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let sub = Subscription(events: Set(events), continuation: continuation)
            self.subscriptions[id] = sub
        }
        logger.info("Subscriber \(id) registered for \(events.map(\.rawValue))")
        return (id, stream)
    }

    /// Cancel a subscription and finish its stream.
    func cancel(id: UUID) {
        if let sub = subscriptions.removeValue(forKey: id) {
            sub.continuation.finish()
            logger.debug("Subscriber \(id) cancelled")
        }
    }

    /// Broadcast an event to all subscribers whose filter includes the event name.
    func emit(_ envelope: IPCEventEnvelope) {
        guard !subscriptions.isEmpty else {
            return
        }
        for (_, sub) in subscriptions where sub.events.contains(envelope.event) {
            sub.continuation.yield(envelope)
        }
    }

    /// Number of active subscriptions (for diagnostics).
    var subscriberCount: Int {
        subscriptions.count
    }
}
