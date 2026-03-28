@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
struct ToastCommandHandlerTests {

    private let handler = ToastCommandHandler()

    @Test("Valid toast returns toastID")
    func validToast() throws {
        let request = ToastRequest(title: "Test", level: .info)
        let payload = try handler.handle(.showToast(request: request))
        guard case let .toastID(id) = payload else {
            Issue.record("Expected .toastID payload")
            return
        }
        #expect(!id.isEmpty)
    }

    @Test("Toast with all fields returns toastID")
    func toastWithAllFields() throws {
        let request = ToastRequest(
            title: "CPU Warning",
            message: "90% exceeded",
            icon: "exclamationmark.triangle",
            level: .warning,
            duration: 10,
            actionLabel: "Open Activity Monitor",
            actionShellCommand: "open -a 'Activity Monitor'"
        )
        let payload = try handler.handle(.showToast(request: request))
        guard case .toastID = payload else {
            Issue.record("Expected .toastID payload")
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
