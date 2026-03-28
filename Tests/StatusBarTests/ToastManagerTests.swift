@testable import StatusBar
import StatusBarKit
import Testing

@MainActor
@Suite(.serialized)
struct ToastManagerTests {

    private let manager = ToastManager.shared

    private func setUp() {
        manager.dismissAll()
    }

    @Test("Post returns non-empty ID")
    func postReturnsID() {
        setUp()
        defer { manager.dismissAll() }
        let id = manager.post(ToastRequest(title: "Hello"))
        #expect(!id.isEmpty)
        #expect(manager.toasts.count == 1)
    }

    @Test("Multiple toasts stack up to max")
    func multipleToastsStack() {
        setUp()
        defer { manager.dismissAll() }
        for i in 0 ..< 6 {
            manager.post(ToastRequest(title: "Toast \(i)", duration: 0))
        }
        // maxVisible is 4, so oldest should be evicted
        #expect(manager.toasts.count == 4)
        #expect(manager.toasts.first?.request.title == "Toast 2")
    }

    @Test("Dismiss removes specific toast")
    func dismissByID() {
        setUp()
        defer { manager.dismissAll() }
        let id1 = manager.post(ToastRequest(title: "A", duration: 0))
        let id2 = manager.post(ToastRequest(title: "B", duration: 0))

        manager.dismiss(id: id1)
        #expect(manager.toasts.count == 1)
        #expect(manager.toasts.first?.id == id2)
    }

    @Test("DismissAll clears queue")
    func dismissAllClears() {
        setUp()
        manager.post(ToastRequest(title: "A", duration: 0))
        manager.post(ToastRequest(title: "B", duration: 0))
        manager.dismissAll()
        #expect(manager.toasts.isEmpty)
    }

    @Test("Update progress clamps value")
    func updateProgress() {
        setUp()
        defer { manager.dismissAll() }
        let id = manager.post(ToastRequest(title: "Loading", duration: 0))
        manager.updateProgress(id: id, value: 0.5)
        #expect(manager.toasts.first?.progress == 0.5)

        manager.updateProgress(id: id, value: 1.5)
        #expect(manager.toasts.first?.progress == 1.0)

        manager.updateProgress(id: id, value: -0.5)
        #expect(manager.toasts.first?.progress == 0.0)
    }

    @Test("Dismiss non-existent ID is a no-op")
    func dismissNonExistent() {
        setUp()
        defer { manager.dismissAll() }
        manager.post(ToastRequest(title: "A", duration: 0))
        manager.dismiss(id: "non-existent")
        #expect(manager.toasts.count == 1)
    }
}
