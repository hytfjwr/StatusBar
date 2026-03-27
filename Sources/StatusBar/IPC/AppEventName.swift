import StatusBarKit

// MARK: - AppEventName

/// Application-specific event names.
/// The SDK's IPC layer uses plain strings; this enum provides type safety within the host app.
enum AppEventName: String, CaseIterable {
    case frontAppSwitched = "front_app_switched"
    case volumeChanged = "volume_changed"
}

// MARK: - IPCEventEnvelope convenience factories

extension IPCEventEnvelope {
    static func frontAppSwitched(appName: String, bundleID: String?) -> Self {
        IPCEventEnvelope(
            event: AppEventName.frontAppSwitched.rawValue,
            payload: .object([
                "appName": .string(appName),
                "bundleID": bundleID.map { .string($0) } ?? .null,
            ])
        )
    }

    static func volumeChanged(volume: Int, muted: Bool) -> Self {
        IPCEventEnvelope(
            event: AppEventName.volumeChanged.rawValue,
            payload: .object([
                "volume": .number(Double(volume)),
                "muted": .bool(muted),
            ])
        )
    }

    static func configReloaded() -> Self {
        IPCEventEnvelope(event: BarEvent.configReloaded)
    }
}
