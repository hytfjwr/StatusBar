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
        let (id, stream) = bus.subscribe(to: [FrontAppEvent.switched])
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
        let (id, stream) = bus.subscribe(to: [VolumeEvent.changed])
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

    // MARK: - Wildcard subscriptions

    @Test("Wildcard subscription matches prefix")
    func wildcardMatchesPrefix() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: ["battery_*"])
        defer { bus.cancel(id: id) }

        let envelope = IPCEventEnvelope.batteryChanged(percent: 80, charging: false, hasBattery: true)
        bus.emit(envelope)

        var received: IPCEventEnvelope?
        for await event in stream {
            received = event
            break
        }
        #expect(received == envelope)
    }

    @Test("Wildcard subscription matches multiple event names")
    func wildcardMatchesMultiple() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: ["battery_*"])
        defer { bus.cancel(id: id) }

        let e1 = IPCEventEnvelope.batteryChanged(percent: 50, charging: true, hasBattery: true)
        let e2 = IPCEventEnvelope.batteryChargingChanged(charging: true)
        bus.emit(e1)
        bus.emit(e2)

        var events: [IPCEventEnvelope] = []
        for await event in stream {
            events.append(event)
            if events.count == 2 {
                break
            }
        }
        #expect(events.count == 2)
        #expect(events[0] == e1)
        #expect(events[1] == e2)
    }

    @Test("Wildcard does not match unrelated events")
    func wildcardDoesNotMatchUnrelated() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: ["battery_*"])
        defer { bus.cancel(id: id) }

        // Emit non-matching event, then matching to unblock stream
        bus.emit(.volumeChanged(volume: 50, muted: false))
        bus.emit(.batteryLow(percent: 10, threshold: 20))

        var received: IPCEventEnvelope?
        for await event in stream {
            received = event
            break
        }
        #expect(received?.event == BatteryEvent.low)
    }

    @Test("Bare * matches all events")
    func bareWildcardMatchesAll() async {
        let bus = EventBus.shared
        let (id, stream) = bus.subscribe(to: ["*"])
        defer { bus.cancel(id: id) }

        let envelope = IPCEventEnvelope.cpuUpdated(percent: 42)
        bus.emit(envelope)

        var received: IPCEventEnvelope?
        for await event in stream {
            received = event
            break
        }
        #expect(received == envelope)
    }

    // MARK: - Rate limiting (emitRaw)

    @Test("emitRaw suppresses within cooldown interval")
    func emitRawSuppressesWithinCooldown() async {
        let bus = EventBus.shared
        bus.resetCooldowns()
        let (id, stream) = bus.subscribe(to: [CPUEvent.updated])
        defer { bus.cancel(id: id) }

        // First emit should pass
        bus.emitRaw(.cpuUpdated(percent: 50), minInterval: 10)
        // Second emit within interval should be suppressed
        bus.emitRaw(.cpuUpdated(percent: 55), minInterval: 10)

        // Emit a transition event to unblock stream after checking
        bus.emit(.configReloaded())

        // Subscribe to both to see what arrives
        let (id2, stream2) = bus.subscribe(to: [CPUEvent.updated, BarEvent.configReloaded])
        defer { bus.cancel(id: id2) }

        bus.emitRaw(.cpuUpdated(percent: 60), minInterval: 10)
        bus.emit(.configReloaded())

        var events: [IPCEventEnvelope] = []
        for await event in stream2 {
            events.append(event)
            if events.count == 1 {
                break
            }
        }
        // Should only get configReloaded (cpu_updated was suppressed)
        #expect(events[0].event == BarEvent.configReloaded)
        bus.resetCooldowns()
    }

    @Test("emitRaw passes after cooldown expires")
    func emitRawPassesAfterCooldown() async {
        let bus = EventBus.shared
        bus.resetCooldowns()
        let (id, stream) = bus.subscribe(to: [CPUEvent.updated])
        defer { bus.cancel(id: id) }

        // With a very short interval, both should pass
        bus.emitRaw(.cpuUpdated(percent: 50), minInterval: 0)
        bus.emitRaw(.cpuUpdated(percent: 55), minInterval: 0)

        var events: [IPCEventEnvelope] = []
        for await event in stream {
            events.append(event)
            if events.count == 2 {
                break
            }
        }
        #expect(events.count == 2)
        bus.resetCooldowns()
    }
}
