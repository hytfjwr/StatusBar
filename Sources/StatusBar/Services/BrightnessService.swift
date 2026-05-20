import AppKit
import CoreGraphics
import Foundation

// MARK: - ManagedDisplay

struct ManagedDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    var brightness: Float
    let isBuiltin: Bool
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

    /// Whether the underlying private framework loaded successfully.
    var isAvailable: Bool {
        DisplayServicesBindings.getBrightness != nil && DisplayServicesBindings.setBrightness != nil
    }

    /// Enumerate online displays whose brightness is controllable via `DisplayServices`.
    ///
    /// Phase 1 scope: Apple displays only. Third-party HDR monitors are excluded because
    /// macOS 15+ exposes their SDR-peak slider through `DisplayServicesGetBrightness`,
    /// which silently no-ops on the actual backlight. They would need DDC/CI support
    /// to be controlled, which is a follow-up.
    func enumerateDisplays() -> [ManagedDisplay] {
        let maxDisplays: UInt32 = 16
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &ids, &count) == .success else {
            return []
        }

        return ids.prefix(Int(count)).compactMap { id -> ManagedDisplay? in
            // Skip the secondary side of a mirror pair — both IDs share the same
            // physical panel, so we only need the primary.
            if CGDisplayIsInMirrorSet(id) != 0, CGDisplayMirrorsDisplay(id) != 0 {
                return nil
            }

            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            let isAppleVendor = CGDisplayVendorNumber(id) == appleVendorID
            guard isBuiltin || isAppleVendor else {
                return nil
            }

            guard let value = getBrightness(id) else {
                return nil
            }

            return ManagedDisplay(
                id: id,
                name: localizedName(for: id),
                brightness: value,
                isBuiltin: isBuiltin
            )
        }
    }

    func getBrightness(_ id: CGDirectDisplayID) -> Float? {
        guard let fn = DisplayServicesBindings.getBrightness else {
            return nil
        }
        var value: Float = 0
        guard fn(id, &value) == 0 else {
            return nil
        }
        return value
    }

    @discardableResult
    func setBrightness(_ value: Float, for id: CGDirectDisplayID) -> Bool {
        guard let fn = DisplayServicesBindings.setBrightness else {
            return false
        }
        let clamped = max(0, min(1, value))
        return fn(id, clamped) == 0
    }

    // MARK: - Private

    /// Apple's PNP vendor ID (`AAPL`). All Apple-built displays report this value.
    private let appleVendorID: UInt32 = 1_552

    private func localizedName(for id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? CGDirectDisplayID) == id
        }) {
            return screen.localizedName
        }
        return "Display \(id)"
    }
}
