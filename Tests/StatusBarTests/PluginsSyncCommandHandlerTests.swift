@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct PluginsSyncCommandHandlerTests {
    private let handler = PluginsSyncCommandHandler()

    @Test("Sync command returns .ok immediately (work runs detached)")
    func returnsOk() throws {
        let payload = try handler.handle(.pluginsSync(frozen: false))
        guard case .ok = payload else {
            Issue.record("Expected .ok payload, got \(payload)")
            return
        }
    }

    @Test("Wrong command case throws unknownCommand")
    func wrongCommandCase() {
        #expect(throws: IPCError.self) {
            try handler.handle(.list)
        }
    }
}
