import Foundation
@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct EventBusTests {

    // MARK: - Basic emit/receive

    @Test("Subscriber receives matching event")
    func receiveMatchingEvent() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: [AppEventName.frontAppSwitched.rawValue])
        defer { bus.cancel(id: id) }

        let envelope = IPCEventEnvelope.frontAppSwitched(appName: "Safari", bundleID: "com.apple.Safari")
        bus.emit(envelope)

        var received: IPCEventEnvelope?
        for await event in stream {
            received = event
            break
        }
        #expect(received == envelope)
    }

    // MARK: - Filter

    @Test("Subscriber does not receive non-matching events")
    func filterNonMatchingEvent() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: [AppEventName.volumeChanged.rawValue])
        defer { bus.cancel(id: id) }

        // Emit an event that doesn't match the subscription.
        bus.emit(.frontAppSwitched(appName: "Xcode", bundleID: nil))

        // Emit a matching event so the stream has something to yield.
        let matching = IPCEventEnvelope.volumeChanged(volume: 50, muted: false)
        bus.emit(matching)

        var received: IPCEventEnvelope?
        for await event in stream {
            received = event
            break
        }
        #expect(received == matching)
    }

    // MARK: - Cancel

    @Test("Cancel finishes the stream")
    func cancelFinishesStream() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: [BarEvent.configReloaded])

        bus.cancel(id: id)

        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: - Multiple subscribers (fanout)

    @Test("Multiple subscribers each receive the event")
    func fanout() async {
        let bus = EventBus.shared

        let (id1, stream1) = bus.subscribe(to: [BarEvent.configReloaded])
        let (id2, stream2) = bus.subscribe(to: [BarEvent.configReloaded])
        defer {
            bus.cancel(id: id1)
            bus.cancel(id: id2)
        }

        let envelope = IPCEventEnvelope.configReloaded()
        bus.emit(envelope)

        var r1: IPCEventEnvelope?
        for await event in stream1 {
            r1 = event
            break
        }

        var r2: IPCEventEnvelope?
        for await event in stream2 {
            r2 = event
            break
        }

        #expect(r1 == envelope)
        #expect(r2 == envelope)
    }
}
