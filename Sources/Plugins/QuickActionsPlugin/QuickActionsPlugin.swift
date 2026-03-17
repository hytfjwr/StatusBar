import StatusBarKit

@MainActor
public struct QuickActionsPlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.statusbar.quick-actions",
        name: "Quick Actions"
    )

    public let widgets: [any StatusBarWidget]

    public init() {
        widgets = [QuickActionsWidget()]
    }
}
