@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct TriggerCommandHandlerTests {

    private let handler = TriggerCommandHandler()

    @Test("Valid trigger returns .ok")
    func validTrigger() throws {
        let payload = try handler.handle(.trigger(event: "com.example.myapp.ping", payload: nil))
        #expect(payload == .ok)
    }

    @Test("Trigger with payload returns .ok")
    func triggerWithPayload() throws {
        let payload = try handler.handle(
            .trigger(event: "com.example.myapp.deploy", payload: .object(["repo": .string("main")]))
        )
        #expect(payload == .ok)
    }

    @Test("Empty event name throws invalidValue")
    func emptyEventName() {
        #expect(throws: IPCError.self) {
            try handler.handle(.trigger(event: "", payload: nil))
        }
    }

    @Test("Wrong command case throws unknownCommand")
    func wrongCommandCase() {
        #expect(throws: IPCError.self) {
            try handler.handle(.list)
        }
    }
}
