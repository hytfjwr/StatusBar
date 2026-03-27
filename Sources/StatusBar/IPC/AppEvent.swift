import StatusBarKit

// MARK: - AppEvent

/// Central catalog of all event name constants.
/// Each constant is defined in its source widget file (e.g., `BatteryEvent`)
/// and re-exported here for discoverability and cross-cutting consumers.
enum AppEvent {
    enum FrontApp {
        static let switched = FrontAppEvent.switched
    }

    enum Volume {
        static let changed = VolumeEvent.changed
        static let muted = VolumeEvent.muted
        static let unmuted = VolumeEvent.unmuted
    }

    enum Battery {
        static let changed = BatteryEvent.changed
        static let chargingChanged = BatteryEvent.chargingChanged
        static let low = BatteryEvent.low
    }

    enum CPU {
        static let updated = CPUEvent.updated
        static let high = CPUEvent.high
    }

    enum Memory {
        static let updated = MemoryEvent.updated
        static let high = MemoryEvent.high
    }

    enum Network {
        static let updated = NetworkEvent.updated
    }

    enum Bluetooth {
        static let devicesChanged = BluetoothEvent.devicesChanged
        static let deviceConnected = BluetoothEvent.deviceConnected
        static let deviceDisconnected = BluetoothEvent.deviceDisconnected
    }

    enum Disk {
        static let updated = DiskEvent.updated
        static let high = DiskEvent.high
    }

    enum InputSource {
        static let changed = InputSourceEvent.changed
    }

    enum MicCamera {
        static let changed = MicCameraEvent.changed
        static let micActivated = MicCameraEvent.micActivated
        static let micDeactivated = MicCameraEvent.micDeactivated
        static let cameraActivated = MicCameraEvent.cameraActivated
        static let cameraDeactivated = MicCameraEvent.cameraDeactivated
    }

    enum FocusTimer {
        static let started = FocusTimerEvent.started
        static let stopped = FocusTimerEvent.stopped
        static let completed = FocusTimerEvent.completed
    }

    enum Calendar {
        static let nextEventChanged = DateEvent.nextEventChanged
    }

    enum Bar {
        static let configReloaded = BarEvent.configReloaded
    }
}

// MARK: - Bar event factory

extension IPCEventEnvelope {
    static func configReloaded() -> Self {
        IPCEventEnvelope(event: AppEvent.Bar.configReloaded)
    }
}
