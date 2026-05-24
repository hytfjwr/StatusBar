@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct TriggerCommandHandlerTests {

    private let handler = TriggerCommandHandler()

    @Test("Valid trigger returns .ok")
    func validTrigger() async throws {
        let payload = try await handler.handle(.trigger(event: "com.example.myapp.ping", payload: nil))
        #expect(payload == .ok)
    }

    @Test("Trigger with payload returns .ok")
    func triggerWithPayload() async throws {
        let payload = try await handler.handle(
            .trigger(event: "com.example.myapp.deploy", payload: .object(["repo": .string("main")]))
        )
        #expect(payload == .ok)
    }

    @Test("Empty event name throws invalidValue")
    func emptyEventName() async {
        await #expect(throws: IPCError.self) {
            try await handler.handle(.trigger(event: "", payload: nil))
        }
    }

    @Test("Wrong command case throws unknownCommand")
    func wrongCommandCase() async {
        await #expect(throws: IPCError.self) {
            try await handler.handle(.list)
        }
    }
}
