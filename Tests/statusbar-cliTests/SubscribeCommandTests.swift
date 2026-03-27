import Foundation
import StatusBarIPC
import Testing

struct SubscribeCommandTests {
    @Test("IPCEventEnvelope round-trips with string event name")
    func envelopeRoundTrip() throws {
        let envelope = IPCEventEnvelope(
            event: "front_app_switched",
            timestamp: 1_000_000,
            payload: .object([
                "appName": .string("Safari"),
                "bundleID": .string("com.apple.Safari"),
            ])
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(IPCEventEnvelope.self, from: data)
        #expect(decoded == envelope)
    }

    @Test("IPCEventEnvelope with nil payload round-trips")
    func envelopeNilPayloadRoundTrip() throws {
        let envelope = IPCEventEnvelope(event: "config_reloaded", timestamp: 1_000_000)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(IPCEventEnvelope.self, from: data)
        #expect(decoded == envelope)
    }

    @Test("Subscribe command accepts arbitrary event names")
    func arbitraryEventNames() throws {
        let request = IPCRequest(command: .subscribe(events: ["custom_plugin_event", "front_app_switched"]))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)
        #expect(decoded == request)
    }
}
