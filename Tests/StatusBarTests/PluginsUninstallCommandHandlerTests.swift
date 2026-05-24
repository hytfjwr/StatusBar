@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct PluginsUninstallCommandHandlerTests {
    private let handler = PluginsUninstallCommandHandler()

    @Test("Wrong command case throws unknownCommand")
    func wrongCommandCase() async {
        await #expect(throws: IPCError.self) {
            try await handler.handle(.list)
        }
    }

    // Note: a test for the unknown-source error path would hit PluginsManager.shared and read
    // the developer's real ~/.config/statusbar/plugins-lock.yml. The unknown-source semantics
    // are exercised by PluginsManagerTests via the DI'd manifestStore — keeping this suite
    // singleton-free.
}
