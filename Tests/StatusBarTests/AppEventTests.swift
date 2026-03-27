@testable import StatusBar
import Testing

/// Pin event name strings so that external scripts relying on `sbar subscribe`
/// are not silently broken by a rename.
@MainActor
struct AppEventTests {

    @Test("FrontApp event names")
    func frontApp() {
        #expect(AppEvent.FrontApp.switched == "front_app_switched")
    }

    @Test("Volume event names")
    func volume() {
        #expect(AppEvent.Volume.changed == "volume_changed")
        #expect(AppEvent.Volume.muted == "volume_muted")
        #expect(AppEvent.Volume.unmuted == "volume_unmuted")
    }

    @Test("Battery event names")
    func battery() {
        #expect(AppEvent.Battery.changed == "battery_changed")
        #expect(AppEvent.Battery.chargingChanged == "battery_charging_changed")
        #expect(AppEvent.Battery.low == "battery_low")
    }

    @Test("CPU event names")
    func cpu() {
        #expect(AppEvent.CPU.updated == "cpu_updated")
        #expect(AppEvent.CPU.high == "cpu_high")
    }

    @Test("Memory event names")
    func memory() {
        #expect(AppEvent.Memory.updated == "memory_updated")
        #expect(AppEvent.Memory.high == "memory_high")
    }

    @Test("Network event names")
    func network() {
        #expect(AppEvent.Network.updated == "network_updated")
    }

    @Test("Bluetooth event names")
    func bluetooth() {
        #expect(AppEvent.Bluetooth.devicesChanged == "bluetooth_devices_changed")
        #expect(AppEvent.Bluetooth.deviceConnected == "bluetooth_device_connected")
        #expect(AppEvent.Bluetooth.deviceDisconnected == "bluetooth_device_disconnected")
    }

    @Test("Disk event names")
    func disk() {
        #expect(AppEvent.Disk.updated == "disk_updated")
        #expect(AppEvent.Disk.high == "disk_high")
    }

    @Test("InputSource event names")
    func inputSource() {
        #expect(AppEvent.InputSource.changed == "input_source_changed")
    }

    @Test("MicCamera event names")
    func micCamera() {
        #expect(AppEvent.MicCamera.changed == "mic_camera_changed")
        #expect(AppEvent.MicCamera.micActivated == "mic_activated")
        #expect(AppEvent.MicCamera.micDeactivated == "mic_deactivated")
        #expect(AppEvent.MicCamera.cameraActivated == "camera_activated")
        #expect(AppEvent.MicCamera.cameraDeactivated == "camera_deactivated")
    }

    @Test("FocusTimer event names")
    func focusTimer() {
        #expect(AppEvent.FocusTimer.started == "focus_timer_started")
        #expect(AppEvent.FocusTimer.stopped == "focus_timer_stopped")
        #expect(AppEvent.FocusTimer.completed == "focus_timer_completed")
    }

    @Test("Calendar event names")
    func calendar() {
        #expect(AppEvent.Calendar.nextEventChanged == "calendar_next_event_changed")
    }

    @Test("Bar event names")
    func bar() {
        #expect(AppEvent.Bar.configReloaded == "config_reloaded")
    }
}
