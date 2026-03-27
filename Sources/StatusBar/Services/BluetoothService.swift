import CoreBluetooth
import Foundation
import IOBluetooth
import IOKit
import OSLog

private let logger = Logger(subsystem: "com.statusbar", category: "BluetoothService")

// MARK: - BluetoothService

final class BluetoothService: NSObject, @unchecked Sendable, CBCentralManagerDelegate {

    /// Instantiating CBCentralManager triggers the TCC Bluetooth permission dialog.
    /// Once the user grants permission, `CBCentralManager.authorization` becomes `.allowedAlways`
    /// and subsequent `poll()` calls can use `IOBluetoothDevice.pairedDevices()`.
    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)

    /// Called when Bluetooth authorization changes to `.allowedAlways`.
    var onAuthorized: (() -> Void)?

    struct BluetoothDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let category: DeviceCategory
        let batteryLevel: Int?

        enum DeviceCategory: String {
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

    /// Enumerate connected Bluetooth devices via IOBluetooth framework + IORegistry battery lookup.
    func poll() -> [BluetoothDevice] {
        // IOBluetoothDevice.pairedDevices() requires TCC Bluetooth permission.
        // Without it (e.g. bare binary outside .app bundle), the process crashes with SIGABRT.
        let auth = CBCentralManager.authorization
        if auth == .notDetermined {
            _ = centralManager // lazy init triggers the TCC permission dialog
            return []
        }
        guard auth == .allowedAlways else {
            return []
        }

        let batteryMap = queryBatteryLevels()
        return queryConnectedDevices(batteryMap: batteryMap)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let auth = CBCentralManager.authorization
        logger.info("Bluetooth authorization: \(auth.rawValue)")
        if auth == .allowedAlways {
            onAuthorized?()
        }
    }

    // MARK: - Device Enumeration (IOBluetooth)

    private func queryConnectedDevices(batteryMap: [String: Int]) -> [BluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        var devices: [BluetoothDevice] = []
        for device in paired where device.isConnected() {
            let name = device.name ?? "Unknown"
            let address = device.addressString ?? "unknown-\(name.lowercased())"
            let category = classify(
                majorClass: UInt32(device.deviceClassMajor),
                minorClass: UInt32(device.deviceClassMinor),
                name: name
            )
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

    // MARK: - Classification

    private func classify(majorClass: UInt32, minorClass: UInt32, name: String) -> BluetoothDevice.DeviceCategory {
        switch majorClass {
        case 0x05: // Peripheral
            switch minorClass & 0x3C {
            case 0x10: return .keyboard
            case 0x20: return .mouse
            case 0x30: return .keyboard // combo keyboard+pointing
            default: break
            }
            if minorClass & 0x0F == 0x02 {
                return .gamepad
            }
            return classifyByName(name)

        case 0x04: // Audio/Video
            return .headphones

        default:
            return classifyByName(name)
        }
    }

    private func classifyByName(_ name: String) -> BluetoothDevice.DeviceCategory {
        let lower = name.lowercased()
        if lower.contains("keyboard") {
            return .keyboard
        }
        if lower.contains("mouse") || lower.contains("magic mouse") {
            return .mouse
        }
        if lower.contains("trackpad") {
            return .trackpad
        }
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("beats") {
            return .headphones
        }
        if lower.contains("controller") || lower.contains("gamepad") {
            return .gamepad
        }
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

            guard let props = serviceProperties(service),
                  let battery = props["BatteryPercent"] as? Int
            else {
                continue
            }

            if let addr = props["DeviceAddress"] as? String {
                result[normalizeAddress(addr)] = battery
            }

            if let product = props["Product"] as? String {
                result[product.lowercased()] = battery
            }
        }

        return result
    }

    private func serviceProperties(_ service: io_object_t) -> [String: Any]? {
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cfDict = propsRef?.takeRetainedValue()
        else {
            return nil
        }
        return cfDict as? [String: Any]
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
