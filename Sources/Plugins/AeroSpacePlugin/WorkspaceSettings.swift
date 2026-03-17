import Foundation
import StatusBarKit

@MainActor
@Observable
final class WorkspaceSettings: WidgetConfigProvider {
    static let shared = WorkspaceSettings()

    let configID = "workspace"
    private var suppressWrite = false

    var updateInterval: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var showAppIcons: Bool {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var appIconSize: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var showEmptySpaces: Bool {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "workspace")
        updateInterval = cfg?["updateInterval"]?.doubleValue ?? 10.0
        showAppIcons = cfg?["showAppIcons"]?.boolValue ?? true
        appIconSize = cfg?["appIconSize"]?.doubleValue ?? 16.0
        showEmptySpaces = cfg?["showEmptySpaces"]?.boolValue ?? false
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        [
            "updateInterval": .double(updateInterval),
            "showAppIcons": .bool(showAppIcons),
            "appIconSize": .double(appIconSize),
            "showEmptySpaces": .bool(showEmptySpaces),
        ]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["updateInterval"]?.doubleValue { updateInterval = v }
        if let v = values["showAppIcons"]?.boolValue { showAppIcons = v }
        if let v = values["appIconSize"]?.doubleValue { appIconSize = v }
        if let v = values["showEmptySpaces"]?.boolValue { showEmptySpaces = v }
    }
}
