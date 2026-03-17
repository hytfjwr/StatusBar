import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "WidgetLayoutStore")

/// Persists widget layout entries via ConfigLoader (YAML).
@MainActor
final class WidgetLayoutStore {
    func load() -> [WidgetLayoutEntry] {
        ConfigLoader.shared.currentConfig.widgets.map(\.asEntry)
    }

    func save(_ entries: [WidgetLayoutEntry]) {
        ConfigLoader.shared.scheduleWrite()
    }
}
