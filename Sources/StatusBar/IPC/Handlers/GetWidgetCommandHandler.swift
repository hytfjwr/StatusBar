import Foundation
import StatusBarKit

// MARK: - GetWidgetCommandHandler

@MainActor
struct GetWidgetCommandHandler: CommandHandling {
    let commandKey = "getWidget"

    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .getWidget(id) = command else {
            throw IPCError.unknownCommand
        }

        guard let entry = WidgetRegistry.shared.layout.first(where: { $0.id == id }) else {
            throw IPCError.widgetNotFound(id: id)
        }

        var settings = WidgetConfigRegistry.shared.exportAll()[id] ?? [:]
        mergeRuntimeState(id: id, into: &settings)
        return .widgetDetail(.make(from: entry, settings: settings))
    }

    /// Merge widget-specific runtime state into the settings map returned via IPC.
    /// Keys are namespaced under `state.` to signal they are read-only and never
    /// persisted to the YAML config. Plain scalars only (`ConfigValue` limitation);
    /// structured values are JSON-encoded strings the caller decodes with `jq`.
    private func mergeRuntimeState(id: String, into settings: inout [String: ConfigValue]) {
        switch id {
        case "bluetooth":
            BluetoothRuntimeState.merge(into: &settings)
        default:
            break
        }
    }
}

// MARK: - BluetoothRuntimeState

@MainActor
private enum BluetoothRuntimeState {
    static func merge(into settings: inout [String: ConfigValue]) {
        guard let widget = BluetoothWidgetLocator.current else {
            return
        }
        let devices = widget.currentDevices
        settings["state.deviceCount"] = .int(devices.count)
        if let json = encodeDevices(devices) {
            settings["state.devices"] = .string(json)
        }
    }

    private static func encodeDevices(_ devices: [BluetoothService.BluetoothDevice]) -> String? {
        let payload = devices.map { device -> [String: Any] in
            var entry: [String: Any] = [
                "id": device.id,
                "name": device.name,
                "category": device.category.rawValue,
            ]
            if let b = device.batteryLevel {
                entry["battery"] = b
            }
            if let l = device.leftBattery {
                entry["batteryLeft"] = l
            }
            if let r = device.rightBattery {
                entry["batteryRight"] = r
            }
            if let c = device.caseBattery {
                entry["batteryCase"] = c
            }
            return entry
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - BluetoothWidgetLocator

/// Holds a weak reference to the live `BluetoothWidget` so the IPC layer can
/// query runtime state (connected devices, batteries) without importing the
/// widget tree or owning it. Registered once in `AppDelegate` during widget setup.
@MainActor
enum BluetoothWidgetLocator {
    private static weak var instance: BluetoothWidget?

    static func register(_ widget: BluetoothWidget) {
        instance = widget
    }

    static var current: BluetoothWidget? {
        instance
    }
}
