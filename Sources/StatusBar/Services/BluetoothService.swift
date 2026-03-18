import Foundation
import IOBluetooth
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

    /// Enumerate connected Bluetooth devices using IOBluetooth native API.
    func poll() -> [BluetoothDevice] {
        let batteryMap = queryIORegistryBatteryLevels()

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return paired.compactMap { device -> BluetoothDevice? in
            guard device.isConnected() else { return nil }

            let name = device.name ?? "Unknown"
            let address = device.addressString ?? UUID().uuidString
            let classOfDevice = device.classOfDevice
            let category = classify(classOfDevice: classOfDevice, name: name)
            let battery = lookupBattery(address: address, name: name, batteryMap: batteryMap)

            return BluetoothDevice(
                id: address,
                name: name,
                category: category,
                batteryLevel: battery
            )
        }
    }

    // MARK: - Classification

    private func classify(classOfDevice: BluetoothClassOfDevice, name: String) -> BluetoothDevice.DeviceCategory {
        let majorClass = (classOfDevice >> 8) & 0x1F
        let minorClass = (classOfDevice >> 2) & 0x3F

        switch majorClass {
        case 0x05:  // Peripheral
            // Minor class bits for peripheral sub-types
            let minorUpper = minorClass & 0x3C  // Upper 4 bits of minor (bits 7:2 shifted)
            if minorUpper == 0x10 { return .keyboard }       // 0x40 >> 2
            if minorUpper == 0x20 { return .mouse }          // 0x80 >> 2
            if minorUpper == 0x30 { return .keyboard }       // 0xC0 >> 2 combo keyboard+pointing
            if minorUpper == 0x02 { return .gamepad }        // 0x08 >> 2 gamepad

            // Fall through to name-based for trackpad etc.
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

    /// Query IORegistry for battery levels from AppleDeviceManagementHIDEventService entries.
    /// Returns a dictionary keyed by normalized device address and product name.
    private func queryIORegistryBatteryLevels() -> [String: Int] {
        var result: [String: Int] = [:]

        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return result }
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

            // Key by device address (normalized) if available
            if let addrRaw = IORegistryEntryCreateCFProperty(
                service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
               let addr = addrRaw as? String {
                let normalized = normalizeAddress(addr)
                result[normalized] = battery
            }

            // Also key by product name for fallback matching
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
        // Try matching by normalized address first
        let normalized = normalizeAddress(address)
        if let level = batteryMap[normalized] {
            return level
        }
        // Fall back to name-based matching
        if let level = batteryMap[name.lowercased()] {
            return level
        }
        return nil
    }

    /// Normalize Bluetooth address to lowercase with consistent separator.
    private func normalizeAddress(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":").trimmingCharacters(in: .whitespaces)
    }
}
