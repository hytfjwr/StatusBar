@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct PluginsInstallCommandHandlerTests {
    private let handler = PluginsInstallCommandHandler()

    @Test("Wrong command case throws unknownCommand")
    func wrongCommandCase() async {
        await #expect(throws: IPCError.self) {
            try await handler.handle(.list)
        }
    }
}
