import Foundation

/// Protocol that all plugins must conform to.
/// Each plugin bundles one or more widgets and their backing services.
@MainActor
public protocol StatusBarPlugin {
    /// Plugin metadata.
    var manifest: PluginManifest { get }

    /// The widgets this plugin provides, in display order.
    var widgets: [any StatusBarWidget] { get }

    /// Register this plugin's widgets to the given registry.
    /// Override for custom registration logic.
    func register(to registry: any WidgetRegistryProtocol)
}

extension StatusBarPlugin {
    public func register(to registry: any WidgetRegistryProtocol) {
        for widget in widgets {
            registry.register(widget)
        }
    }
}
