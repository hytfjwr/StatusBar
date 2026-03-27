import StatusBarKit

// MARK: - AppEvent

/// Application-level event name constants, organized by domain.
/// Mirrors the `BarEvent` (SDK) pattern: caseless enums used as namespaces.
///
/// Three granularity levels:
/// - **Raw** (`*_changed` / `*_updated`): emitted on every value change
/// - **Transition** (`*_started`, `*_activated`, etc.): discrete state flips
/// - **Threshold** (`*_low`, `*_high`): configurable boundary crossings
enum AppEvent {

    // MARK: - FrontApp

    enum FrontApp {
        static let switched = "front_app_switched"
    }

    // MARK: - Volume

    enum Volume {
        static let changed = "volume_changed"
        static let muted = "volume_muted"
        static let unmuted = "volume_unmuted"
    }

    // MARK: - Battery

    enum Battery {
        static let changed = "battery_changed"
        static let chargingChanged = "battery_charging_changed"
        static let low = "battery_low"
    }

    // MARK: - CPU

    enum CPU {
        static let updated = "cpu_updated"
        static let high = "cpu_high"
    }

    // MARK: - Memory

    enum Memory {
        static let updated = "memory_updated"
        static let high = "memory_high"
    }

    // MARK: - Network

    enum Network {
        static let updated = "network_updated"
    }

    // MARK: - Bluetooth

    enum Bluetooth {
        static let devicesChanged = "bluetooth_devices_changed"
        static let deviceConnected = "bluetooth_device_connected"
        static let deviceDisconnected = "bluetooth_device_disconnected"
    }

    // MARK: - Disk

    enum Disk {
        static let updated = "disk_updated"
        static let high = "disk_high"
    }

    // MARK: - InputSource

    enum InputSource {
        static let changed = "input_source_changed"
    }

    // MARK: - MicCamera

    enum MicCamera {
        static let changed = "mic_camera_changed"
        static let micActivated = "mic_activated"
        static let micDeactivated = "mic_deactivated"
        static let cameraActivated = "camera_activated"
        static let cameraDeactivated = "camera_deactivated"
    }

    // MARK: - FocusTimer

    enum FocusTimer {
        static let started = "focus_timer_started"
        static let stopped = "focus_timer_stopped"
        static let completed = "focus_timer_completed"
    }

    // MARK: - Calendar

    enum Calendar {
        static let nextEventChanged = "calendar_next_event_changed"
    }

    // MARK: - Bar (re-export SDK constants)

    enum Bar {
        static let configReloaded = BarEvent.configReloaded
    }
}
