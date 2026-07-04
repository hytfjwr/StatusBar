import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "CustomWidgetCoordinator")

// MARK: - ValidationResult

struct ValidationResult: Equatable {
    var valid: [CustomWidgetConfig]
    var errors: [String]
}

// MARK: - Diff

struct Diff: Equatable {
    var added: [CustomWidgetConfig]
    var removedIDs: [String] // config ids
    var changed: [CustomWidgetConfig]
}

// MARK: - CustomWidgetCoordinator

/// Validates, registers, and hot-reload-syncs YAML-declared custom script widgets.
@MainActor
final class CustomWidgetCoordinator {
    static let shared = CustomWidgetCoordinator()

    /// Active widgets keyed by config id (NOT widgetID).
    private var activeWidgets: [String: CustomScriptWidget] = [:]
    private var activeConfigs: [String: CustomWidgetConfig] = [:]

    private init() {}

    // MARK: - Validation

    /// Validates raw configs: non-empty id matching `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`,
    /// non-empty script, unique ids (first occurrence wins).
    nonisolated static func validate(_ raw: [CustomWidgetConfig]) -> ValidationResult {
        let idPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/
        var valid: [CustomWidgetConfig] = []
        var errors: [String] = []
        var seenIDs = Set<String>()

        for (index, config) in raw.enumerated() {
            guard !config.id.isEmpty else {
                errors.append("customWidgets entry #\(index + 1): missing id")
                continue
            }
            guard config.id.wholeMatch(of: idPattern) != nil else {
                errors.append("customWidgets '\(config.id)': invalid id (use letters, digits, - or _)")
                continue
            }
            guard !config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errors.append("customWidgets '\(config.id)': missing script")
                continue
            }
            guard !seenIDs.contains(config.id) else {
                errors.append("customWidgets '\(config.id)': duplicate id")
                continue
            }
            seenIDs.insert(config.id)
            valid.append(config)
        }

        return ValidationResult(valid: valid, errors: errors)
    }

    // MARK: - Diff

    nonisolated static func diff(
        current: [String: CustomWidgetConfig],
        desired: [CustomWidgetConfig]
    ) -> Diff {
        var added: [CustomWidgetConfig] = []
        var changed: [CustomWidgetConfig] = []
        var desiredIDs = Set<String>()

        for config in desired {
            desiredIDs.insert(config.id)
            if let existing = current[config.id] {
                if existing != config {
                    changed.append(config)
                }
            } else {
                added.append(config)
            }
        }

        let removedIDs = current.keys.filter { !desiredIDs.contains($0) }.sorted()

        return Diff(added: added, removedIDs: removedIDs, changed: changed)
    }

    // MARK: - Startup Registration

    /// Called once from AppDelegate during launch, before finalizeRegistration().
    /// Registers widgets but does NOT start them — StatusBarController.startAll() does.
    func registerAll(from configs: [CustomWidgetConfig], into registry: WidgetRegistry) {
        let result = Self.validate(configs)
        for message in result.errors {
            logger.warning("\(message)")
        }
        for config in result.valid {
            let widget = CustomScriptWidget(config: config)
            registry.register(widget)
            activeWidgets[config.id] = widget
            activeConfigs[config.id] = config
        }
    }

    // MARK: - Hot Reload

    /// Called from ConfigLoader.applyNewConfig on hot-reload.
    func sync(with configs: [CustomWidgetConfig], registry: WidgetRegistry) {
        let result = Self.validate(configs)
        let changes = Self.diff(current: activeConfigs, desired: result.valid)

        // Removed: drop layout entries too (the user deleted the widget).
        if !changes.removedIDs.isEmpty {
            let widgetIDs = Set(changes.removedIDs.compactMap { activeConfigs[$0]?.widgetID })
            registry.unregisterWidgets(ids: widgetIDs, preserveLayout: false)
            for id in changes.removedIDs {
                activeWidgets.removeValue(forKey: id)
                activeConfigs.removeValue(forKey: id)
            }
        }

        // Changed: re-register with the same layout slot.
        for config in changes.changed {
            registry.unregisterWidgets(ids: [config.widgetID], preserveLayout: true)
            let widget = CustomScriptWidget(config: config)
            registry.register(widget)
            activeWidgets[config.id] = widget
            activeConfigs[config.id] = config
        }

        // Added: register fresh.
        for config in changes.added {
            let widget = CustomScriptWidget(config: config)
            registry.register(widget)
            activeWidgets[config.id] = widget
            activeConfigs[config.id] = config
        }

        registry.finalizeRegistration()

        // Start newly created widgets whose layout entry is visible.
        // start() is idempotent, so a later applyLayout() visibility pass double-starting is harmless.
        for config in changes.added + changes.changed {
            let isVisible = registry.layout.first { $0.id == config.widgetID }?.isVisible ?? true
            if isVisible {
                activeWidgets[config.id]?.start()
            }
        }

        if !result.errors.isEmpty {
            let summary = result.errors.prefix(2).joined(separator: "\n")
            ToastManager.shared.post(ToastRequest(
                title: "Custom Widgets",
                message: result.errors.count > 2 ? summary + "\n…" : summary,
                level: .warning
            ))
            for message in result.errors {
                logger.warning("\(message)")
            }
        }
    }
}
