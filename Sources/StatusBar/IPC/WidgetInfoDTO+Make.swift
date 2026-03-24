import StatusBarKit

extension WidgetInfoDTO {
    @MainActor
    static func make(from entry: WidgetLayoutEntry, settings: [String: ConfigValue]) -> WidgetInfoDTO {
        WidgetInfoDTO(
            id: entry.id,
            displayName: WidgetRegistry.displayName(for: entry.id),
            position: entry.section,
            sortIndex: entry.sortIndex,
            isVisible: entry.isVisible,
            settings: settings
        )
    }
}
