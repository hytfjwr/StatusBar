@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct PluginsListCommandHandlerTests {
    private let handler = PluginsListCommandHandler()

    @Test("List command returns pluginList payload")
    func returnsPluginList() throws {
        let payload = try handler.handle(.pluginsList)
        guard case .pluginList = payload else {
            Issue.record("Expected .pluginList payload, got \(payload)")
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
