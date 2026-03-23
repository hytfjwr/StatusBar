@testable import StatusBar
import Testing

@MainActor
struct BatteryServiceTests {

    // MARK: - Observer token management

    @Test("addObserver returns unique tokens")
    func uniqueTokens() {
        let service = BatteryService.shared
        service.removeAllObservers()

        let token1 = service.addObserver { _, _, _ in }
        let token2 = service.addObserver { _, _, _ in }
        #expect(token1 != token2)

        service.removeAllObservers()
    }

    @Test("removeObserver removes only the targeted observer")
    func removeSpecificObserver() {
        let service = BatteryService.shared
        service.removeAllObservers()

        var called1 = false
        var called2 = false

        let token1 = service.addObserver { _, _, _ in called1 = true }
        _ = service.addObserver { _, _, _ in called2 = true }

        service.removeObserver(token1)
        service.poll()

        #expect(!called1)
        #expect(called2)

        service.removeAllObservers()
    }

    @Test("removeObserver with already-removed token is a no-op")
    func removeIdempotent() {
        let service = BatteryService.shared
        service.removeAllObservers()

        let token = service.addObserver { _, _, _ in }
        service.removeObserver(token)
        service.removeObserver(token) // should not crash

        service.removeAllObservers()
    }
}
