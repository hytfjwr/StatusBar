import StatusBarKit

// MARK: - IPCEventEnvelope factories

extension IPCEventEnvelope {

    // MARK: FrontApp

    static func frontAppSwitched(appName: String, bundleID: String?) -> Self {
        IPCEventEnvelope(
            event: AppEvent.FrontApp.switched,
            payload: .object([
                "appName": .string(appName),
                "bundleID": bundleID.map { .string($0) } ?? .null,
            ])
        )
    }

    // MARK: Volume

    static func volumeChanged(volume: Int, muted: Bool) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Volume.changed,
            payload: .object([
                "volume": .number(Double(volume)),
                "muted": .bool(muted),
            ])
        )
    }

    static func volumeMuted() -> Self {
        IPCEventEnvelope(event: AppEvent.Volume.muted)
    }

    static func volumeUnmuted() -> Self {
        IPCEventEnvelope(event: AppEvent.Volume.unmuted)
    }

    // MARK: Battery

    static func batteryChanged(percent: Int, charging: Bool, hasBattery: Bool) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Battery.changed,
            payload: .object([
                "percent": .number(Double(percent)),
                "charging": .bool(charging),
                "hasBattery": .bool(hasBattery),
            ])
        )
    }

    static func batteryChargingChanged(charging: Bool) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Battery.chargingChanged,
            payload: .object([
                "charging": .bool(charging),
            ])
        )
    }

    static func batteryLow(percent: Int, threshold: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Battery.low,
            payload: .object([
                "percent": .number(Double(percent)),
                "threshold": .number(Double(threshold)),
            ])
        )
    }

    // MARK: CPU

    static func cpuUpdated(percent: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.CPU.updated,
            payload: .object([
                "percent": .number(Double(percent)),
            ])
        )
    }

    static func cpuHigh(usagePercent: Int, threshold: Int, sustainedSeconds: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.CPU.high,
            payload: .object([
                "usagePercent": .number(Double(usagePercent)),
                "threshold": .number(Double(threshold)),
                "sustainedSeconds": .number(Double(sustainedSeconds)),
            ])
        )
    }

    // MARK: Memory

    static func memoryUpdated(percent: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Memory.updated,
            payload: .object([
                "percent": .number(Double(percent)),
            ])
        )
    }

    static func memoryHigh(usagePercent: Int, threshold: Int, sustainedSeconds: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Memory.high,
            payload: .object([
                "usagePercent": .number(Double(usagePercent)),
                "threshold": .number(Double(threshold)),
                "sustainedSeconds": .number(Double(sustainedSeconds)),
            ])
        )
    }

    // MARK: Network

    static func networkUpdated(downloadBytesPerSec: Double, uploadBytesPerSec: Double) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Network.updated,
            payload: .object([
                "downloadBytesPerSec": .number(downloadBytesPerSec),
                "uploadBytesPerSec": .number(uploadBytesPerSec),
            ])
        )
    }

    // MARK: Bluetooth

    static func bluetoothDevicesChanged(connectedCount: Int, deviceNames: [String]) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Bluetooth.devicesChanged,
            payload: .object([
                "connectedCount": .number(Double(connectedCount)),
                "deviceNames": .array(deviceNames.map { .string($0) }),
            ])
        )
    }

    static func bluetoothDeviceConnected(name: String, category: String) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Bluetooth.deviceConnected,
            payload: .object([
                "name": .string(name),
                "category": .string(category),
            ])
        )
    }

    static func bluetoothDeviceDisconnected(name: String) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Bluetooth.deviceDisconnected,
            payload: .object([
                "name": .string(name),
            ])
        )
    }

    // MARK: Disk

    static func diskUpdated(usedPercent: Int, usedBytes: Int64, totalBytes: Int64) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Disk.updated,
            payload: .object([
                "usedPercent": .number(Double(usedPercent)),
                "usedBytes": .number(Double(usedBytes)),
                "totalBytes": .number(Double(totalBytes)),
            ])
        )
    }

    static func diskHigh(usedPercent: Int, threshold: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.Disk.high,
            payload: .object([
                "usedPercent": .number(Double(usedPercent)),
                "threshold": .number(Double(threshold)),
            ])
        )
    }

    // MARK: InputSource

    static func inputSourceChanged(abbreviation: String) -> Self {
        IPCEventEnvelope(
            event: AppEvent.InputSource.changed,
            payload: .object([
                "abbreviation": .string(abbreviation),
            ])
        )
    }

    // MARK: MicCamera

    static func micCameraChanged(micActive: Bool, cameraActive: Bool) -> Self {
        IPCEventEnvelope(
            event: AppEvent.MicCamera.changed,
            payload: .object([
                "micActive": .bool(micActive),
                "cameraActive": .bool(cameraActive),
            ])
        )
    }

    static func micActivated() -> Self {
        IPCEventEnvelope(event: AppEvent.MicCamera.micActivated)
    }

    static func micDeactivated() -> Self {
        IPCEventEnvelope(event: AppEvent.MicCamera.micDeactivated)
    }

    static func cameraActivated() -> Self {
        IPCEventEnvelope(event: AppEvent.MicCamera.cameraActivated)
    }

    static func cameraDeactivated() -> Self {
        IPCEventEnvelope(event: AppEvent.MicCamera.cameraDeactivated)
    }

    // MARK: FocusTimer

    static func focusTimerStarted(mode: String, durationSeconds: Int) -> Self {
        IPCEventEnvelope(
            event: AppEvent.FocusTimer.started,
            payload: .object([
                "mode": .string(mode),
                "durationSeconds": .number(Double(durationSeconds)),
            ])
        )
    }

    static func focusTimerStopped() -> Self {
        IPCEventEnvelope(event: AppEvent.FocusTimer.stopped)
    }

    static func focusTimerCompleted(mode: String) -> Self {
        IPCEventEnvelope(
            event: AppEvent.FocusTimer.completed,
            payload: .object([
                "mode": .string(mode),
            ])
        )
    }

    // MARK: Calendar

    static func calendarNextEventChanged(title: String?, startDate: String?, timeUntilStart: Double?) -> Self {
        var fields: [String: JSONValue] = [:]
        if let title {
            fields["title"] = .string(title)
        }
        if let startDate {
            fields["startDate"] = .string(startDate)
        }
        if let timeUntilStart {
            fields["timeUntilStartSeconds"] = .number(timeUntilStart)
        }
        return IPCEventEnvelope(
            event: AppEvent.Calendar.nextEventChanged,
            payload: fields.isEmpty ? nil : .object(fields)
        )
    }

    // MARK: Bar

    static func configReloaded() -> Self {
        IPCEventEnvelope(event: AppEvent.Bar.configReloaded)
    }
}
