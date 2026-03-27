import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "EventBus")

// MARK: - EventBus

/// Pub/sub hub for IPC event subscriptions.
/// Producers call `emit(_:)` on the main actor; each subscriber receives
/// events through an `AsyncStream` filtered by their subscribed event names.
///
/// Supports wildcard subscriptions: a pattern ending in `*` matches any event
/// whose name starts with the prefix (e.g., `"battery_*"` matches `"battery_changed"`).
@MainActor
final class EventBus {
    static let shared = EventBus()

    private var subscriptions: [UUID: Subscription] = [:]

    /// Per-event-name cooldown timestamps for rate-limited raw events.
    private var rawEventCooldowns: [String: Date] = [:]

    /// Default minimum interval between raw events of the same name.
    static let defaultRawInterval: TimeInterval = 0.25

    private struct Subscription {
        let patterns: [Pattern]
        let continuation: AsyncStream<IPCEventEnvelope>.Continuation

        struct Pattern {
            let isWildcard: Bool
            /// For exact match: the full event name. For wildcard: the prefix before `*`.
            let value: String
        }

        func matches(_ eventName: String) -> Bool {
            for pattern in patterns {
                if pattern.isWildcard {
                    if eventName.hasPrefix(pattern.value) {
                        return true
                    }
                } else {
                    if eventName == pattern.value {
                        return true
                    }
                }
            }
            return false
        }
    }

    private init() {}

    /// Create a new subscription that yields events matching `events`.
    /// Patterns ending in `*` are treated as prefix wildcards.
    /// Returns a unique ID (for cancellation) and the stream to consume.
    func subscribe(to events: [String]) -> (id: UUID, stream: AsyncStream<IPCEventEnvelope>) {
        let id = UUID()
        let patterns = events.map { name -> Subscription.Pattern in
            if name.hasSuffix("*") {
                return .init(isWildcard: true, value: String(name.dropLast()))
            }
            return .init(isWildcard: false, value: name)
        }
        let stream = AsyncStream<IPCEventEnvelope>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let sub = Subscription(patterns: patterns, continuation: continuation)
            self.subscriptions[id] = sub
        }
        logger.info("Subscriber \(id) registered for \(events)")
        return (id, stream)
    }

    /// Cancel a subscription and finish its stream.
    func cancel(id: UUID) {
        if let sub = subscriptions.removeValue(forKey: id) {
            sub.continuation.finish()
            if subscriptions.isEmpty {
                rawEventCooldowns.removeAll(keepingCapacity: true)
            }
            logger.debug("Subscriber \(id) cancelled")
        }
    }

    /// Broadcast a transition or threshold event to all matching subscribers.
    /// Never rate-limited.
    func emit(_ envelope: IPCEventEnvelope) {
        guard !subscriptions.isEmpty else {
            return
        }
        for (_, sub) in subscriptions where sub.matches(envelope.event) {
            sub.continuation.yield(envelope)
        }
    }

    /// Broadcast a raw (high-frequency) event, rate-limited per event name.
    /// If the same event name was emitted within `minInterval`, the event is dropped.
    func emitRaw(_ envelope: IPCEventEnvelope, minInterval: TimeInterval = EventBus.defaultRawInterval) {
        guard !subscriptions.isEmpty else {
            return
        }
        let now = Date()
        if let lastEmit = rawEventCooldowns[envelope.event],
           now.timeIntervalSince(lastEmit) < minInterval
        {
            return
        }
        rawEventCooldowns[envelope.event] = now
        emit(envelope)
    }

    /// Number of active subscriptions (for diagnostics).
    var subscriberCount: Int {
        subscriptions.count
    }

    /// Reset rate-limiting state (for testing).
    func resetCooldowns() {
        rawEventCooldowns.removeAll()
    }
}
