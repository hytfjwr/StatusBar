import StatusBarIPC
import Testing

struct SubscribeCommandTests {
    @Test("BarEventName initializes from valid raw values")
    func validEventNames() {
        #expect(BarEventName(rawValue: "front_app_switched") == .frontAppSwitched)
        #expect(BarEventName(rawValue: "volume_changed") == .volumeChanged)
        #expect(BarEventName(rawValue: "config_reloaded") == .configReloaded)
    }

    @Test("BarEventName returns nil for unknown raw value")
    func unknownEventName() {
        #expect(BarEventName(rawValue: "nonexistent_event") == nil)
        #expect(BarEventName(rawValue: "") == nil)
    }

    @Test("BarEventName.allCases contains expected events")
    func allCasesComplete() {
        let names = Set(BarEventName.allCases.map(\.rawValue))
        #expect(names.contains("front_app_switched"))
        #expect(names.contains("volume_changed"))
        #expect(names.contains("config_reloaded"))
        #expect(names.count == 3)
    }
}
