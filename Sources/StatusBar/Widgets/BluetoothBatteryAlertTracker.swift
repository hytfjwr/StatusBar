import Foundation

// MARK: - BluetoothBatteryAlertTracker

/// Pure threshold state machine for the Bluetooth low-battery notification.
/// Call `evaluate(...)` with the current device list and user preferences; it
/// returns the alerts that should fire this tick and mutates internal state so
/// the next call suppresses repeats until the reading rises back above the
/// threshold. Side effects (toasts, event emission) live outside so the state
/// machine stays unit-testable with no app singletons involved.
///
/// State key layout:
///   - Single-battery devices: `<device.id>`
///   - AirPods components: `<device.id>:left` and `<device.id>:right`
struct BluetoothBatteryAlertTracker {
    struct Alert: Equatable {
        let deviceID: String
        let deviceName: String
        let component: String?
        let percent: Int
    }

    private var notifiedKeys: Set<String> = []

    mutating func evaluate(
        devices: [BluetoothService.BluetoothDevice],
        enabled: Bool,
        threshold: Int
    ) -> [Alert] {
        guard enabled else {
            // When the toggle goes off, forget history so re-enabling re-notifies.
            notifiedKeys.removeAll(keepingCapacity: true)
            return []
        }

        var alerts: [Alert] = []
        var stillTrackable: Set<String> = []

        for device in devices {
            if device.hasAirPodsDetail {
                for (component, reading) in [("left", device.leftBattery), ("right", device.rightBattery)] {
                    guard let reading else {
                        continue
                    }
                    if let alert = record(
                        device: device,
                        component: component,
                        percent: reading,
                        threshold: threshold,
                        tracked: &stillTrackable
                    ) {
                        alerts.append(alert)
                    }
                }
            } else if let battery = device.batteryLevel {
                if let alert = record(
                    device: device,
                    component: nil,
                    percent: battery,
                    threshold: threshold,
                    tracked: &stillTrackable
                ) {
                    alerts.append(alert)
                }
            }
        }

        // Drop any keys that are no longer reporting — disconnected devices or
        // a component that stopped sending a reading. Without this the tracker
        // would silently suppress a re-connection at a low level.
        notifiedKeys.formIntersection(stillTrackable)

        return alerts
    }

    private mutating func record(
        device: BluetoothService.BluetoothDevice,
        component: String?,
        percent: Int,
        threshold: Int,
        tracked: inout Set<String>
    ) -> Alert? {
        let key = component.map { "\(device.id):\($0)" } ?? device.id
        tracked.insert(key)
        if percent <= threshold {
            guard notifiedKeys.insert(key).inserted else {
                return nil
            }
            return Alert(
                deviceID: device.id,
                deviceName: device.name,
                component: component,
                percent: percent
            )
        }
        notifiedKeys.remove(key)
        return nil
    }
}
