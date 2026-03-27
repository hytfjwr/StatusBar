import StatusBarKit

// MARK: - EventEmitting

/// Protocol for types that emit events to the IPC EventBus.
///
/// Provides two emission methods:
/// - `emit(_:)`: for state transitions and threshold events (never suppressed)
/// - `emitRaw(_:)`: for high-frequency raw events (rate-limited per event name)
@MainActor
protocol EventEmitting {
    func emit(_ envelope: IPCEventEnvelope)
    func emitRaw(_ envelope: IPCEventEnvelope)
}

extension EventEmitting {
    func emit(_ envelope: IPCEventEnvelope) {
        EventBus.shared.emit(envelope)
    }

    func emitRaw(_ envelope: IPCEventEnvelope) {
        EventBus.shared.emitRaw(envelope)
    }
}
