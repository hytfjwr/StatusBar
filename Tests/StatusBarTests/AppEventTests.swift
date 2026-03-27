@testable import StatusBar
import StatusBarKit
import Testing

/// Pin event name strings so that external scripts relying on `sbar subscribe`
/// are not silently broken by a rename.
@MainActor
struct AppEventTests {

    @Test("FrontApp event names")
    func frontApp() {
        #expect(FrontAppEvent.switched == "front_app_switched")
    }

    @Test("Volume event names")
    func volume() {
        #expect(VolumeEvent.changed == "volume_changed")
        #expect(VolumeEvent.muted == "volume_muted")
        #expect(VolumeEvent.unmuted == "volume_unmuted")
    }

    @Test("Battery event names")
    func battery() {
        #expect(BatteryEvent.changed == "battery_changed")
        #expect(BatteryEvent.chargingChanged == "battery_charging_changed")
        #expect(BatteryEvent.low == "battery_low")
    }

    @Test("CPU event names")
    func cpu() {
        #expect(CPUEvent.updated == "cpu_updated")
        #expect(CPUEvent.high == "cpu_high")
    }

    @Test("Memory event names")
    func memory() {
        #expect(MemoryEvent.updated == "memory_updated")
        #expect(MemoryEvent.high == "memory_high")
    }

    @Test("Network event names")
    func network() {
        #expect(NetworkEvent.updated == "network_updated")
    }

    @Test("Bluetooth event names")
    func bluetooth() {
        #expect(BluetoothEvent.devicesChanged == "bluetooth_devices_changed")
        #expect(BluetoothEvent.deviceConnected == "bluetooth_device_connected")
        #expect(BluetoothEvent.deviceDisconnected == "bluetooth_device_disconnected")
    }

    @Test("Disk event names")
    func disk() {
        #expect(DiskEvent.updated == "disk_updated")
        #expect(DiskEvent.high == "disk_high")
    }

    @Test("InputSource event names")
    func inputSource() {
        #expect(InputSourceEvent.changed == "input_source_changed")
    }

    @Test("MicCamera event names")
    func micCamera() {
        #expect(MicCameraEvent.changed == "mic_camera_changed")
        #expect(MicCameraEvent.micActivated == "mic_activated")
        #expect(MicCameraEvent.micDeactivated == "mic_deactivated")
        #expect(MicCameraEvent.cameraActivated == "camera_activated")
        #expect(MicCameraEvent.cameraDeactivated == "camera_deactivated")
    }

    @Test("FocusTimer event names")
    func focusTimer() {
        #expect(FocusTimerEvent.started == "focus_timer_started")
        #expect(FocusTimerEvent.stopped == "focus_timer_stopped")
        #expect(FocusTimerEvent.completed == "focus_timer_completed")
    }

    @Test("Calendar event names")
    func calendar() {
        #expect(DateEvent.nextEventChanged == "calendar_next_event_changed")
    }

    @Test("Bar event names")
    func bar() {
        #expect(BarEvent.configReloaded == "config_reloaded")
    }
}
