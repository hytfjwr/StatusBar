import Foundation
import IOKit
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

    /// Enumerate connected Bluetooth devices via IOKit IORegistry (no TCC permission required).
    func poll() -> [BluetoothDevice] {
        let batteryMap = queryBatteryLevels()
        return queryConnectedDevices(batteryMap: batteryMap)
    }

    // MARK: - Device Enumeration (IORegistry)

    private func queryConnectedDevices(batteryMap: [String: Int]) -> [BluetoothDevice] {
        let matching = IOServiceMatching("IOBluetoothDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [BluetoothDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let props = serviceProperties(service) else { continue }

            // Only include connected devices
            guard let connected = props["Connected"] as? Bool, connected else { continue }

            let name = props["Name"] as? String ?? "Unknown"
            let address = (props["DeviceAddress"] as? String) ?? UUID().uuidString
            let classOfDevice = props["ClassOfDevice"] as? UInt32 ?? 0
            let category = classify(classOfDevice: classOfDevice, name: name)
            let battery = lookupBattery(address: address, name: name, batteryMap: batteryMap)

            devices.append(BluetoothDevice(
                id: address,
                name: name,
                category: category,
                batteryLevel: battery
            ))
        }

        return devices
    }

    private func serviceProperties(_ service: io_object_t) -> [String: Any]? {
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cfDict = propsRef?.takeRetainedValue()
        else { return nil }
        return cfDict as? [String: Any]
    }

    // MARK: - Classification

    private func classify(classOfDevice: UInt32, name: String) -> BluetoothDevice.DeviceCategory {
        let majorClass = (classOfDevice >> 8) & 0x1F
        let minorClass = (classOfDevice >> 2) & 0x3F

        switch majorClass {
        case 0x05:  // Peripheral
            let minorUpper = minorClass & 0x3C
            if minorUpper == 0x10 { return .keyboard }
            if minorUpper == 0x20 { return .mouse }
            if minorUpper == 0x30 { return .keyboard }  // combo keyboard+pointing
            if minorUpper == 0x02 { return .gamepad }
            return classifyByName(name)

        case 0x04:  // Audio/Video
            return .headphones

        default:
            return classifyByName(name)
        }
    }

    private func classifyByName(_ name: String) -> BluetoothDevice.DeviceCategory {
        let lower = name.lowercased()
        if lower.contains("keyboard") { return .keyboard }
        if lower.contains("mouse") || lower.contains("magic mouse") { return .mouse }
        if lower.contains("trackpad") { return .trackpad }
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("beats") { return .headphones }
        if lower.contains("controller") || lower.contains("gamepad") { return .gamepad }
        return .generic
    }

    // MARK: - Battery (IORegistry)

    private func queryBatteryLevels() -> [String: Int] {
        var result: [String: Int] = [:]

        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let batteryRaw = IORegistryEntryCreateCFProperty(
                service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
                  let battery = batteryRaw as? Int
            else { continue }

            if let addrRaw = IORegistryEntryCreateCFProperty(
                service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
               let addr = addrRaw as? String {
                result[normalizeAddress(addr)] = battery
            }

            if let prodRaw = IORegistryEntryCreateCFProperty(
                service, "Product" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
               let product = prodRaw as? String {
                result[product.lowercased()] = battery
            }
        }

        return result
    }

    private func lookupBattery(address: String, name: String, batteryMap: [String: Int]) -> Int? {
        if let level = batteryMap[normalizeAddress(address)] {
            return level
        }
        if let level = batteryMap[name.lowercased()] {
            return level
        }
        return nil
    }

    private func normalizeAddress(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":").trimmingCharacters(in: .whitespaces)
    }
}
