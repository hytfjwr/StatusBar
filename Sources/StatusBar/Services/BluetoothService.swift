import CoreBluetooth
import Foundation
import IOBluetooth
import IOKit
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "BluetoothService")

// MARK: - BluetoothService

final class BluetoothService: NSObject, @unchecked Sendable, CBCentralManagerDelegate {

    /// Instantiating CBCentralManager triggers the TCC Bluetooth permission dialog.
    /// Once the user grants permission, `CBCentralManager.authorization` becomes `.allowedAlways`
    /// and subsequent `poll()` calls can use `IOBluetoothDevice.pairedDevices()`.
    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)

    /// Called when Bluetooth authorization changes to `.allowedAlways`.
    var onAuthorized: (() -> Void)?

    /// Called on the main queue after an asynchronous `system_profiler` refresh updates the battery cache.
    /// Widgets can hook this to re-poll and pick up newly-arrived AirPods battery data.
    var onBatteryCacheRefreshed: (() -> Void)?

    struct BluetoothDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let category: DeviceCategory
        /// Best-effort primary battery (single-battery device or combined/main for AirPods).
        let batteryLevel: Int?
        /// AirPods left earbud.
        let leftBattery: Int?
        /// AirPods right earbud.
        let rightBattery: Int?
        /// AirPods case.
        let caseBattery: Int?

        var hasAirPodsDetail: Bool {
            leftBattery != nil || rightBattery != nil || caseBattery != nil
        }

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

    /// Detailed battery decomposition returned by richer sources (IORegistry AirPods keys, `system_profiler`).
    struct DetailedBattery: Equatable {
        let main: Int?
        let left: Int?
        let right: Int?
        let caseLevel: Int?
    }

    /// `system_profiler SPBluetoothDataType` cache. Populated asynchronously because the
    /// underlying command takes ~1-3s and must never block the main poll.
    private let cacheLock = NSLock()
    private var batteryCache: [String: DetailedBattery] = [:]
    private var cacheTimestamp: Date?
    private var refreshInFlight = false

    private static let cacheTTL: TimeInterval = 60

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

        let hidBattery = queryHIDBatteryLevels()
        let detailed = readCache()
        maybeKickOffCacheRefresh()
        return queryConnectedDevices(hidBattery: hidBattery, detailed: detailed)
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

    private func queryConnectedDevices(
        hidBattery: [String: Int],
        detailed: [String: DetailedBattery]
    ) -> [BluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        var devices: [BluetoothDevice] = []
        for device in paired where device.isConnected() {
            let name = device.name ?? "Unknown"
            let address = device.addressString ?? "unknown-\(name.lowercased())"
            let normalizedAddr = normalizeAddress(address)
            let category = classify(
                majorClass: UInt32(device.deviceClassMajor),
                minorClass: UInt32(device.deviceClassMinor),
                name: name
            )

            let detail = detailed[normalizedAddr]
            let hid = hidBattery[normalizedAddr] ?? hidBattery[name.lowercased()]
            let primary = detail?.main ?? hid

            devices.append(BluetoothDevice(
                id: address,
                name: name,
                category: category,
                batteryLevel: primary,
                leftBattery: detail?.left,
                rightBattery: detail?.right,
                caseBattery: detail?.caseLevel
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

    // MARK: - HID Battery (IORegistry, Magic devices)

    private func queryHIDBatteryLevels() -> [String: Int] {
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

    // MARK: - AirPods-style Battery (IORegistry recursive scan)

    /// Walk the entire IORegistry looking for services exposing AirPods-style
    /// `BatteryPercentLeft/Right/Case` keys. Keyed by the service's `DeviceAddress`.
    private func queryDetailedBatteriesFromIORegistry() -> [String: DetailedBattery] {
        var result: [String: DetailedBattery] = [:]
        var iterator: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, options, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            guard let props = serviceProperties(entry) else {
                continue
            }

            let left = Self.int(props["BatteryPercentLeft"])
            let right = Self.int(props["BatteryPercentRight"])
            let caseLevel = Self.int(props["BatteryPercentCase"])
            let combined = Self.int(props["BatteryPercentCombined"]) ?? Self.int(props["BatteryPercent"])

            guard left != nil || right != nil || caseLevel != nil || combined != nil else {
                continue
            }

            guard let addr = (props["DeviceAddress"] as? String) ?? (props["SerialNumber"] as? String) else {
                continue
            }

            result[normalizeAddress(addr)] = DetailedBattery(
                main: combined,
                left: left,
                right: right,
                caseLevel: caseLevel
            )
        }

        return result
    }

    // MARK: - system_profiler Cache

    private func readCache() -> [String: DetailedBattery] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return batteryCache
    }

    private func maybeKickOffCacheRefresh() {
        cacheLock.lock()
        let fresh = cacheTimestamp.map { Date().timeIntervalSince($0) < Self.cacheTTL } ?? false
        let shouldRefresh = !fresh && !refreshInFlight
        if shouldRefresh {
            refreshInFlight = true
        }
        cacheLock.unlock()

        guard shouldRefresh else {
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            await self?.performCacheRefresh()
        }
    }

    private func performCacheRefresh() async {
        // IORegistry walk is a full-tree recursive enumeration — run it here on
        // the background queue alongside `system_profiler` so neither touches
        // the main thread during `poll()`.
        let fromIOReg = queryDetailedBatteriesFromIORegistry()
        let fromSP = await Self.fetchSystemProfilerBatteries()

        // IORegistry is fresher than the periodic `system_profiler` snapshot; prefer it.
        let merged = fromSP.merging(fromIOReg) { _, ioreg in ioreg }

        cacheLock.withLock {
            batteryCache = merged
            cacheTimestamp = Date()
            refreshInFlight = false
        }

        DispatchQueue.main.async { [weak self] in
            self?.onBatteryCacheRefreshed?()
        }
    }

    private static func fetchSystemProfilerBatteries() async -> [String: DetailedBattery] {
        do {
            let result = try await ShellCommand.runWithResult(
                "/usr/sbin/system_profiler",
                arguments: ["SPBluetoothDataType", "-json", "-timeout", "3"],
                timeout: 5
            )
            return parseSystemProfilerJSON(Data(result.stdout.utf8))
        } catch {
            logger.debug("system_profiler failed: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Parse `system_profiler SPBluetoothDataType -json` output into a map of device-address → battery.
    /// Format has shifted across macOS versions; this uses a defensive recursive walk.
    /// Exposed `internal` for unit testing.
    static func parseSystemProfilerJSON(_ data: Data?) -> [String: DetailedBattery] {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data)
        else {
            return [:]
        }
        var result: [String: DetailedBattery] = [:]
        walk(obj) { dict in
            guard let addr = dict["device_address"] as? String else {
                return
            }
            let main = parsePercent(dict["device_batteryLevelMain"])
            let left = parsePercent(dict["device_batteryLevelLeft"])
            let right = parsePercent(dict["device_batteryLevelRight"])
            let caseLevel = parsePercent(dict["device_batteryLevelCase"])
            guard main != nil || left != nil || right != nil || caseLevel != nil else {
                return
            }
            let key = normalize(addr)
            result[key] = DetailedBattery(main: main, left: left, right: right, caseLevel: caseLevel)
        }
        return result
    }

    private static func walk(_ obj: Any, _ visit: ([String: Any]) -> Void) {
        if let dict = obj as? [String: Any] {
            visit(dict)
            for (_, value) in dict {
                walk(value, visit)
            }
        } else if let arr = obj as? [Any] {
            for value in arr {
                walk(value, visit)
            }
        }
    }

    private static func parsePercent(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber {
            return number.intValue
        }
        guard let string = raw as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "% "))
        return Int(trimmed)
    }

    // MARK: - Helpers

    private func serviceProperties(_ service: io_object_t) -> [String: Any]? {
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cfDict = propsRef?.takeRetainedValue()
        else {
            return nil
        }
        return cfDict as? [String: Any]
    }

    private static func int(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }

    private func normalizeAddress(_ address: String) -> String {
        Self.normalize(address)
    }

    fileprivate static func normalize(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":").trimmingCharacters(in: .whitespaces)
    }
}
