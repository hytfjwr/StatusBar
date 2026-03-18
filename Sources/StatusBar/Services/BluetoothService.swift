import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "BluetoothService")

final class BluetoothService: @unchecked Sendable {

    struct BluetoothDevice: Identifiable {
        let id: String
        let name: String
        let category: DeviceCategory
        let batteryLevel: Int?

        enum DeviceCategory {
            case headphones
            case keyboard
            case mouse
            case trackpad
            case gamepad
            case generic

            var iconName: String {
                switch self {
                case .headphones: "headphones"
                case .keyboard: "keyboard"
                case .mouse: "computermouse"
                case .trackpad: "hand.tap"
                case .gamepad: "gamecontroller"
                case .generic: "dot.radiowaves.left.and.right"
                }
            }
        }
    }

    /// Enumerate connected Bluetooth devices via system_profiler (supports both classic and BLE).
    func poll() async -> [BluetoothDevice] {
        do {
            let output = try await ShellCommand.run("system_profiler", arguments: ["SPBluetoothDataType", "-json"])
            guard let data = output.data(using: .utf8),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = root["SPBluetoothDataType"] as? [[String: Any]],
                  let entry = entries.first,
                  let connected = entry["device_connected"] as? [[String: Any]]
            else { return [] }

            return connected.compactMap { dict -> BluetoothDevice? in
                guard let (name, props) = dict.first,
                      let props = props as? [String: Any]
                else { return nil }

                let address = props["device_address"] as? String ?? UUID().uuidString
                let minorType = (props["device_minorType"] as? String) ?? ""
                let category = classify(minorType: minorType, name: name)
                let battery = parseBattery(props)

                return BluetoothDevice(
                    id: address,
                    name: name,
                    category: category,
                    batteryLevel: battery
                )
            }
        } catch {
            logger.debug("Bluetooth poll failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Classification

    private func classify(minorType: String, name: String) -> BluetoothDevice.DeviceCategory {
        let type = minorType.lowercased()
        if type.contains("keyboard") { return .keyboard }
        if type.contains("mouse") { return .mouse }
        if type.contains("trackpad") { return .trackpad }
        if type.contains("headphone") || type.contains("headset") { return .headphones }
        if type.contains("gamepad") || type.contains("joystick") { return .gamepad }

        // Fall back to name-based classification
        let lower = name.lowercased()
        if lower.contains("keyboard") { return .keyboard }
        if lower.contains("mouse") || lower.contains("magic mouse") { return .mouse }
        if lower.contains("trackpad") { return .trackpad }
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("beats") { return .headphones }
        if lower.contains("controller") || lower.contains("gamepad") { return .gamepad }

        return .generic
    }

    // MARK: - Battery

    private func parseBattery(_ props: [String: Any]) -> Int? {
        // Try single battery level first, then left/right averages
        if let level = percentValue(props["device_batteryLevel"]) {
            return level
        }
        let left = percentValue(props["device_batteryLevelLeft"])
        let right = percentValue(props["device_batteryLevelRight"])
        if let l = left, let r = right {
            return (l + r) / 2
        }
        return left ?? right
    }

    private func percentValue(_ value: Any?) -> Int? {
        guard let str = value as? String else { return nil }
        // "80%" -> 80
        return Int(str.replacingOccurrences(of: "%", with: ""))
    }
}
