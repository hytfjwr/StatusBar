import AppKit
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "com.statusbar", category: "BrightnessService")

// MARK: - DisplayKind

enum DisplayKind: Hashable {
    /// Built-in laptop / iMac panel — driven via DisplayServices SPI.
    case builtin
    /// External display whose brightness responds to DisplayServices
    /// (Apple-branded externals, plus some HDR monitors that macOS controls
    /// through the same SPI as the System Settings slider).
    case displayServicesExternal
    /// External display driven via DDC/CI over the CoreDisplay IOAVService SPI.
    case ddc
}

// MARK: - ManagedDisplay

struct ManagedDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    var brightness: Float
    let kind: DisplayKind
}

// MARK: - DisplayServicesBindings

/// Private framework binding loaded lazily via `dlopen`.
/// No additional entitlement is required: the framework is system-signed
/// and `disable-library-validation` already covers the dylib plugin loader.
private enum DisplayServicesBindings {
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let getBrightness: GetFn? = load("DisplayServicesGetBrightness")
    static let setBrightness: SetFn? = load("DisplayServicesSetBrightness")

    private static func load<T>(_ symbol: String) -> T? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ) else {
            return nil
        }
        guard let sym = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }
}

// MARK: - BrightnessService

@MainActor
final class BrightnessService {
    static let shared = BrightnessService()

    private init() {}

    private let ddc = DDCService.shared

    /// Whether at least one control path (DisplayServices or DDC) is available.
    var isAvailable: Bool {
        DisplayServicesBindings.getBrightness != nil
    }

    /// Enumerate online displays, classifying each by control path and seeding
    /// the initial brightness value.
    ///
    /// Strategy: try `DisplayServices` first for every display. If the SPI returns
    /// a value, use it — this covers the built-in panel, Apple-branded externals,
    /// and any third-party display whose brightness the System Settings slider
    /// already drives. Only when DisplayServices declines do we fall back to DDC/CI.
    func enumerateDisplays() async -> [ManagedDisplay] {
        let maxDisplays: UInt32 = 16
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &ids, &count) == .success else {
            logger.warning("CGGetOnlineDisplayList failed")
            return []
        }

        var results: [ManagedDisplay] = []
        var ddcCandidates: [CGDirectDisplayID] = []

        for id in ids.prefix(Int(count)) {
            // Skip the secondary side of a mirror pair — both IDs share the same
            // physical panel, so we only need the primary.
            if CGDisplayIsInMirrorSet(id) != 0, CGDisplayMirrorsDisplay(id) != 0 {
                continue
            }

            let isBuiltin = CGDisplayIsBuiltin(id) != 0

            if let value = getBrightnessViaDisplayServices(id) {
                let kind: DisplayKind = isBuiltin ? .builtin : .displayServicesExternal
                results.append(ManagedDisplay(
                    id: id,
                    name: localizedName(for: id),
                    brightness: value,
                    kind: kind
                ))
            } else {
                ddcCandidates.append(id)
            }
        }

        if !ddcCandidates.isEmpty {
            let discovered = await ddc.discover(candidates: ddcCandidates)
            for entry in discovered {
                let name = localizedName(for: entry.id, fallback: entry.productName)
                results.append(ManagedDisplay(
                    id: entry.id,
                    name: name,
                    brightness: entry.brightness,
                    kind: .ddc
                ))
            }
        }
        return results
    }

    func getBrightness(_ id: CGDirectDisplayID, kind: DisplayKind) async -> Float? {
        switch kind {
        case .builtin,
             .displayServicesExternal:
            getBrightnessViaDisplayServices(id)
        case .ddc:
            await ddc.getBrightness(id)
        }
    }

    @discardableResult
    func setBrightness(_ value: Float, for id: CGDirectDisplayID, kind: DisplayKind) async -> Bool {
        switch kind {
        case .builtin,
             .displayServicesExternal:
            setBrightnessViaDisplayServices(value, for: id)
        case .ddc:
            await ddc.setBrightness(value, for: id)
        }
    }

    /// Drop cached IOAVService handles. Call when the screen topology changes —
    /// IOAVService is bound to a specific I2C transport and survives unplug only
    /// in undefined ways.
    func invalidateExternalCache() async {
        await ddc.invalidateCache()
    }

    // MARK: - DisplayServices implementation

    private func getBrightnessViaDisplayServices(_ id: CGDirectDisplayID) -> Float? {
        guard let fn = DisplayServicesBindings.getBrightness else {
            return nil
        }
        var value: Float = 0
        guard fn(id, &value) == 0 else {
            return nil
        }
        return value
    }

    private func setBrightnessViaDisplayServices(_ value: Float, for id: CGDirectDisplayID) -> Bool {
        guard let fn = DisplayServicesBindings.setBrightness else {
            return false
        }
        let clamped = max(0, min(1, value))
        return fn(id, clamped) == 0
    }

    // MARK: - Private

    private func localizedName(
        for id: CGDirectDisplayID, fallback: String = ""
    ) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? CGDirectDisplayID) == id
        }) {
            return screen.localizedName
        }
        if !fallback.isEmpty {
            return fallback
        }
        return "Display \(id)"
    }
}
