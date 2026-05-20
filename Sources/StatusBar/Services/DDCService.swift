import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import os

private let logger = Logger(subsystem: "com.statusbar", category: "DDCService")

// MARK: - Private symbol bindings

/// Opaque AVService reference. Treated as a CF type so ARC handles retain/release.
typealias IOAVService = CFTypeRef

private enum CoreDisplayBindings {
    typealias CreateWithServiceFn = @convention(c) (
        CFAllocator?, io_service_t
    ) -> Unmanaged<CFTypeRef>?
    typealias WriteI2CFn = @convention(c) (
        CFTypeRef, UInt32, UInt32, UnsafePointer<UInt8>, UInt32
    ) -> Int32
    typealias ReadI2CFn = @convention(c) (
        CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32
    ) -> Int32
    typealias CreateInfoDictFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    static let createWithService: CreateWithServiceFn? = load("IOAVServiceCreateWithService")
    static let writeI2C: WriteI2CFn? = load("IOAVServiceWriteI2C")
    static let readI2C: ReadI2CFn? = load("IOAVServiceReadI2C")
    static let createInfoDict: CreateInfoDictFn? = load("CoreDisplay_DisplayCreateInfoDictionary")

    // dlopen handle is opened once at process start and never reassigned, so the
    // pointer is safe to share across actors despite the raw type being non-Sendable.
    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? = {
        // CoreDisplay is technically a public framework but the IOAVService SPI
        // is unexported. dlopen + dlsym is covered by disable-library-validation.
        let candidates = [
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
        ]
        for path in candidates {
            if let opened = dlopen(path, RTLD_LAZY) {
                return opened
            }
        }
        return nil
    }()

    private static func load<T>(_ symbol: String) -> T? {
        guard let handle, let sym = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }
}

// MARK: - DDC packet constants

private let ddcDisplayAddress: UInt8 = 0x37
private let ddcDataAddress: UInt8 = 0x51
private let vcpBrightness: UInt8 = 0x10

// MARK: - DDCService

/// Talks DDC/CI to external monitors via the CoreDisplay IOAVService SPI.
///
/// Apple Silicon only: the I2C transport on Intel Macs goes through
/// `IOFramebuffer` instead of `IOAVService` and is not covered here.
actor DDCService {
    static let shared = DDCService()

    private var displays: [CGDirectDisplayID: Entry] = [:]

    private struct Entry {
        let service: IOAVService
        var vcpMax: UInt16
        var lastWriteAt: ContinuousClock.Instant?
    }

    struct Discovered: Sendable {
        let id: CGDirectDisplayID
        let brightness: Float
        let vcpMax: UInt16
        let productName: String
    }

    var isAvailable: Bool {
        CoreDisplayBindings.createWithService != nil
            && CoreDisplayBindings.writeI2C != nil
            && CoreDisplayBindings.readI2C != nil
    }

    /// Drop all cached IOAVService handles. Call when the display topology changes
    /// (NSApplication.didChangeScreenParametersNotification) since hot-unplug
    /// invalidates the underlying I2C transport.
    func invalidateCache() {
        displays.removeAll()
    }

    /// Discover DDC-capable external displays among the given CG display IDs.
    /// Performs an initial brightness GET; displays that don't reply are excluded.
    func discover(candidates: [CGDirectDisplayID]) -> [Discovered] {
        guard isAvailable else {
            logger.warning(
                """
                DDC unavailable — CoreDisplay symbol load failed \
                (createWithService=\(CoreDisplayBindings.createWithService != nil), \
                writeI2C=\(CoreDisplayBindings.writeI2C != nil), \
                readI2C=\(CoreDisplayBindings.readI2C != nil))
                """
            )
            return []
        }
        displays.removeAll()

        let scanned = scanIORegistry()
        let matches = matchServices(scanned, to: candidates)

        var found: [Discovered] = []
        for match in matches {
            guard let result = readVCP(service: match.service, vcp: vcpBrightness) else {
                logger.warning(
                    "DDC VCP 0x10 GET failed for display \(match.displayID) (\(match.productName))"
                )
                continue
            }
            let vcpMax = max(result.max, 1)
            let entry = Entry(service: match.service, vcpMax: vcpMax, lastWriteAt: nil)
            displays[match.displayID] = entry
            let brightness = min(1, Float(result.current) / Float(vcpMax))
            found.append(
                Discovered(
                    id: match.displayID,
                    brightness: brightness,
                    vcpMax: vcpMax,
                    productName: match.productName
                )
            )
        }
        return found
    }

    func getBrightness(_ id: CGDirectDisplayID) -> Float? {
        guard let entry = displays[id] else {
            return nil
        }
        // Skip a poll read while a write is still settling. DDC writes can take
        // 100ms+ to propagate and reading in that window often returns stale or
        // corrupt values.
        if let lastWrite = entry.lastWriteAt,
           lastWrite.duration(to: .now) < .milliseconds(250)
        {
            return nil
        }
        guard let result = readVCP(service: entry.service, vcp: vcpBrightness) else {
            return nil
        }
        return min(1, Float(result.current) / Float(entry.vcpMax))
    }

    @discardableResult
    func setBrightness(_ value: Float, for id: CGDirectDisplayID) -> Bool {
        guard var entry = displays[id] else {
            return false
        }
        let clamped = max(0, min(1, value))
        let scaled = UInt16((clamped * Float(entry.vcpMax)).rounded())
        guard writeVCP(service: entry.service, vcp: vcpBrightness, value: scaled) else {
            return false
        }
        entry.lastWriteAt = .now
        displays[id] = entry
        return true
    }

    // MARK: - DDC I/O

    private func readVCP(service: IOAVService, vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        var send: [UInt8] = [0x01, vcp]
        var reply = [UInt8](repeating: 0, count: 11)
        guard performDDC(service: service, send: &send, reply: &reply) else {
            return nil
        }
        let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maxValue)
    }

    private func writeVCP(service: IOAVService, vcp: UInt8, value: UInt16) -> Bool {
        var send: [UInt8] = [0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)]
        var reply: [UInt8] = []
        return performDDC(service: service, send: &send, reply: &reply)
    }

    /// MCCS/DDC packet format:
    ///   [0x80 | (payload_len + 1), payload_len, ...payload, checksum]
    /// Checksum seed is `(displayAddress << 1) ^ dataAddress` for multi-byte sends
    /// (write or read-request) and `displayAddress << 1` for single-byte sends.
    /// Read reply checksum seed is 0x50 — see MonitorControl Arm64DDC.swift.
    private func performDDC(
        service: IOAVService,
        send: inout [UInt8],
        reply: inout [UInt8]
    ) -> Bool {
        guard let write = CoreDisplayBindings.writeI2C else {
            return false
        }
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let seed = send.count == 1
            ? ddcDisplayAddress << 1
            : (ddcDisplayAddress << 1) ^ ddcDataAddress
        packet[packet.count - 1] = checksum(seed: seed, bytes: packet, end: packet.count - 2)

        let maxAttempts = 5
        for _ in 0 ..< maxAttempts {
            usleep(10_000)
            var success = packet.withUnsafeBufferPointer { buf -> Bool in
                guard let base = buf.baseAddress else {
                    return false
                }
                return write(
                    service, UInt32(ddcDisplayAddress), UInt32(ddcDataAddress),
                    base, UInt32(buf.count)
                ) == 0
            }
            if !reply.isEmpty, success, let read = CoreDisplayBindings.readI2C {
                usleep(50_000)
                let readOK = reply.withUnsafeMutableBufferPointer { buf -> Bool in
                    guard let base = buf.baseAddress else {
                        return false
                    }
                    return read(service, UInt32(ddcDisplayAddress), 0, base, UInt32(buf.count)) == 0
                }
                if readOK {
                    let want = checksum(seed: 0x50, bytes: reply, end: reply.count - 2)
                    success = want == reply[reply.count - 1]
                } else {
                    success = false
                }
            }
            if success {
                return true
            }
            usleep(20_000)
        }
        return false
    }

    private func checksum(seed: UInt8, bytes: [UInt8], end: Int) -> UInt8 {
        var chk = seed
        for index in 0 ... end {
            chk ^= bytes[index]
        }
        return chk
    }

    // MARK: - IORegistry scan + matching

    private struct ScannedEntry {
        let edidUUID: String
        let location: String
        let manufacturerID: String
        let productName: String
        let serialNumber: Int64
        let alphanumericSerial: String
        let serviceLocation: Int
        let service: IOAVService
    }

    private struct Match {
        let displayID: CGDirectDisplayID
        let service: IOAVService
        let productName: String
    }

    /// Walk IOService and pair each framebuffer (AppleCLCD2 / IOMobileFramebufferShim)
    /// with the following external DCPAVServiceProxy.
    private func scanIORegistry() -> [ScannedEntry] {
        guard let createAV = CoreDisplayBindings.createWithService else {
            return []
        }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var current = FramebufferProps()
        var entries: [ScannedEntry] = []
        var serviceLocation = 0
        let frameBufferNames = ["AppleCLCD2", "IOMobileFramebufferShim"]

        while case let next = IOIteratorNext(iterator), next != IO_OBJECT_NULL {
            defer { IOObjectRelease(next) }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(next, &nameBuffer) == KERN_SUCCESS else {
                continue
            }
            let name = nameBuffer.withUnsafeBufferPointer { buf -> String in
                guard let base = buf.baseAddress else {
                    return ""
                }
                return String(cString: base)
            }

            if frameBufferNames.contains(where: { name.contains($0) }) {
                current = readFramebufferProps(entry: next)
                serviceLocation += 1
                current.serviceLocation = serviceLocation
            } else if name.contains("DCPAVServiceProxy") {
                guard let location = stringProperty(of: next, key: "Location"),
                      location == "External",
                      let avRef = createAV(kCFAllocatorDefault, next)?.takeRetainedValue()
                else {
                    continue
                }
                entries.append(ScannedEntry(
                    edidUUID: current.edidUUID,
                    location: location,
                    manufacturerID: current.manufacturerID,
                    productName: current.productName,
                    serialNumber: current.serialNumber,
                    alphanumericSerial: current.alphanumericSerial,
                    serviceLocation: current.serviceLocation,
                    service: avRef
                ))
            }
        }
        return entries
    }

    private struct FramebufferProps {
        var edidUUID: String = ""
        var manufacturerID: String = ""
        var productName: String = ""
        var serialNumber: Int64 = 0
        var alphanumericSerial: String = ""
        var serviceLocation: Int = 0
    }

    private func readFramebufferProps(entry: io_service_t) -> FramebufferProps {
        var props = FramebufferProps()
        if let uuid = stringProperty(of: entry, key: "EDID UUID") {
            props.edidUUID = uuid
        }
        if let displayAttrs = dictProperty(of: entry, key: "DisplayAttributes"),
           let productAttrs = displayAttrs["ProductAttributes"] as? [String: Any]
        {
            props.manufacturerID = (productAttrs["ManufacturerID"] as? String) ?? ""
            props.productName = (productAttrs["ProductName"] as? String) ?? ""
            props.serialNumber = (productAttrs["SerialNumber"] as? Int64) ?? 0
            props.alphanumericSerial = (productAttrs["AlphanumericSerialNumber"] as? String) ?? ""
        }
        return props
    }

    private func stringProperty(of entry: io_service_t, key: String) -> String? {
        guard let prop = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else {
            return nil
        }
        return prop.takeRetainedValue() as? String
    }

    private func dictProperty(of entry: io_service_t, key: String) -> [String: Any]? {
        guard let prop = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else {
            return nil
        }
        return prop.takeRetainedValue() as? [String: Any]
    }

    /// Score-based matching adapted from MonitorControl Arm64DDC.swift.
    /// EDID UUID slices encode vendor/product/manufacture date/image size — we
    /// compare those against `CoreDisplay_DisplayCreateInfoDictionary`. Serial
    /// numbers from the registry rarely match the CG-reported value, but contribute
    /// when they do. Service location is used as the final tiebreaker so identical
    /// monitors on different ports don't collide.
    private func matchServices(
        _ scanned: [ScannedEntry], to candidates: [CGDirectDisplayID]
    ) -> [Match] {
        var scored: [Int: [(displayID: CGDirectDisplayID, entry: ScannedEntry)]] = [:]
        for displayID in candidates {
            for entry in scanned {
                let score = matchScore(displayID: displayID, entry: entry)
                scored[score, default: []].append((displayID, entry))
            }
        }
        var takenDisplays = Set<CGDirectDisplayID>()
        var takenLocations = Set<Int>()
        var results: [Match] = []
        for score in stride(from: 20, through: 1, by: -1) {
            guard let bucket = scored[score] else {
                continue
            }
            for candidate in bucket {
                if takenDisplays.contains(candidate.displayID)
                    || takenLocations.contains(candidate.entry.serviceLocation)
                {
                    continue
                }
                takenDisplays.insert(candidate.displayID)
                takenLocations.insert(candidate.entry.serviceLocation)
                results.append(Match(
                    displayID: candidate.displayID,
                    service: candidate.entry.service,
                    productName: candidate.entry.productName
                ))
            }
        }
        return results
    }

    private func matchScore(displayID: CGDirectDisplayID, entry: ScannedEntry) -> Int {
        guard let createInfo = CoreDisplayBindings.createInfoDict,
              let info = createInfo(displayID)?.takeRetainedValue() as NSDictionary?
        else {
            return 0
        }
        var score = 0

        if let vendor = info[kDisplayVendorID] as? Int64,
           let product = info[kDisplayProductID] as? Int64,
           let week = info[kDisplayWeekOfManufacture] as? Int64,
           let year = info[kDisplayYearOfManufacture] as? Int64,
           let vSize = info[kDisplayVerticalImageSize] as? Int64,
           let hSize = info[kDisplayHorizontalImageSize] as? Int64
        {
            let edid = entry.edidUUID
            let probes: [(offset: Int, expected: String)] = [
                (0, hex16(vendor)),
                (4, hex16le(product)),
                (19, hex8(week) + hex8(year - 1990)),
                (30, hex8(hSize / 10) + hex8(vSize / 10)),
            ]
            for probe in probes where probe.expected != "0000" {
                let endIndex = probe.offset + 4
                guard edid.count >= endIndex else {
                    continue
                }
                let start = edid.index(edid.startIndex, offsetBy: probe.offset)
                let end = edid.index(edid.startIndex, offsetBy: endIndex)
                if String(edid[start ..< end]).uppercased() == probe.expected {
                    score += 1
                }
            }
        }

        if let serial = info[kDisplaySerialNumber] as? Int64,
           serial != 0, entry.serialNumber == serial
        {
            score += 1
        }
        if let nameMap = info["DisplayProductName"] as? [String: String],
           let name = nameMap["en_US"] ?? nameMap.first?.value,
           !entry.productName.isEmpty,
           name.lowercased() == entry.productName.lowercased()
        {
            score += 1
        }
        return score
    }

    private func hex16(_ value: Int64) -> String {
        let bounded = UInt16(max(0, min(value, 0xFFFF)))
        return String(format: "%04X", bounded)
    }

    private func hex16le(_ value: Int64) -> String {
        let bounded = UInt16(max(0, min(value, 0xFFFF)))
        let lo = UInt8(bounded & 0xFF)
        let hi = UInt8((bounded >> 8) & 0xFF)
        return String(format: "%02X%02X", lo, hi)
    }

    private func hex8(_ value: Int64) -> String {
        let bounded = UInt8(max(0, min(value, 0xFF)))
        return String(format: "%02X", bounded)
    }
}
