import Foundation
import StatusBarKit

@MainActor
struct SetGlobalCommandHandler: CommandHandling {
    let commandKey = "setGlobal"

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func handle(_ command: IPCCommand) throws -> IPCPayload {
        guard case let .setGlobal(keyPath, value) = command else {
            throw IPCError.unknownCommand
        }

        let p = PreferencesModel.shared

        switch keyPath {
        // Bar
        case "bar.height":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.barHeight = CGFloat(v)
        case "bar.cornerRadius":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.barCornerRadius = CGFloat(v)
        case "bar.margin":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.barMargin = CGFloat(v)
        case "bar.yOffset":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.barYOffset = CGFloat(v)
        case "bar.widgetSpacing":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.widgetSpacing = CGFloat(v)
        case "bar.widgetPaddingH":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.widgetPaddingH = CGFloat(v)
        // Appearance
        case "appearance.accent":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.accentHex = try parseHex(s, keyPath: keyPath)
        case "appearance.textPrimaryOpacity":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.textPrimaryOpacity = v
        case "appearance.textSecondaryOpacity":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.textSecondaryOpacity = v
        case "appearance.textTertiaryOpacity":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.textTertiaryOpacity = v
        case "appearance.green":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.greenHex = try parseHex(s, keyPath: keyPath)
        case "appearance.yellow":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.yellowHex = try parseHex(s, keyPath: keyPath)
        case "appearance.red":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.redHex = try parseHex(s, keyPath: keyPath)
        case "appearance.cyan":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.cyanHex = try parseHex(s, keyPath: keyPath)
        case "appearance.purple":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.purpleHex = try parseHex(s, keyPath: keyPath)
        case "appearance.barTint":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.barTintHex = try parseHex(s, keyPath: keyPath)
        case "appearance.barTintOpacity":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.barTintOpacity = v
        case "appearance.shadowEnabled":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.shadowEnabled = v
        case "appearance.popupCornerRadius":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.popupCornerRadius = CGFloat(v)
        case "appearance.popupPadding":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.popupPadding = CGFloat(v)
        // Typography
        case "typography.iconFontSize":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.iconFontSize = CGFloat(v)
        case "typography.labelFontSize":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.labelFontSize = CGFloat(v)
        case "typography.smallFontSize":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.smallFontSize = CGFloat(v)
        case "typography.monoFontSize":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.monoFontSize = CGFloat(v)
        // Graphs
        case "graphs.width":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.graphWidth = CGFloat(v)
        case "graphs.height":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.graphHeight = CGFloat(v)
        case "graphs.dataPoints":
            guard let v = value.intValue else {
                throw typeError(keyPath, "integer")
            }
            p.graphDataPoints = v
        case "graphs.cpuColor":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.cpuGraphHex = try parseHex(s, keyPath: keyPath)
        case "graphs.memoryColor":
            guard let s = value.stringValue else {
                throw typeError(keyPath, "hex string")
            }
            p.memoryGraphHex = try parseHex(s, keyPath: keyPath)
        // Behavior
        case "behavior.autoHide":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.autoHideEnabled = v
        case "behavior.autoHideDwellTime":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.autoHideDwellTime = v
        case "behavior.autoHideFadeDuration":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.autoHideFadeDuration = v
        case "behavior.launchAtLogin":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.launchAtLogin = v
        case "behavior.hideInFullscreen":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.hideInFullscreen = v
        // Notifications
        case "notifications.batteryLow":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.notifyBatteryLow = v
        case "notifications.batteryThreshold":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.batteryThreshold = v
        case "notifications.cpuHigh":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.notifyCPUHigh = v
        case "notifications.cpuThreshold":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.cpuThreshold = v
        case "notifications.cpuSustainedDuration":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.cpuSustainedDuration = v
        case "notifications.memoryHigh":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.notifyMemoryHigh = v
        case "notifications.memoryThreshold":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.memoryThreshold = v
        case "notifications.memorySustainedDuration":
            guard let v = value.doubleValue else {
                throw typeError(keyPath, "number")
            }
            p.memorySustainedDuration = v
        // Developer
        case "devMode":
            guard let v = value.boolValue else {
                throw typeError(keyPath, "boolean")
            }
            p.devModeEnabled = v
        default:
            throw IPCError.invalidKeyPath(keyPath)
        }

        return .ok
    }

    // MARK: - Helpers

    private func typeError(_ keyPath: String, _ expected: String) -> IPCError {
        .invalidValue(key: keyPath, reason: "expected \(expected)")
    }

    private func parseHex(_ string: String, keyPath: String) throws -> UInt32 {
        let hex = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            throw IPCError.invalidValue(key: keyPath, reason: "expected hex color like #007AFF")
        }
        return value
    }
}
