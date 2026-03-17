// This file is auto-generated from plugins.json.
// Do not edit manually. Run `make generate` to regenerate.

import StatusBarKit
import AeroSpacePlugin
import SpotifyPlugin
import DockerPlugin
import VPNPlugin
import QuickActionsPlugin

@MainActor
enum PluginLoader {
    static func registerAll(to registry: any WidgetRegistryProtocol) {
        AeroSpacePlugin().register(to: registry)
        SpotifyPlugin().register(to: registry)
        DockerPlugin().register(to: registry)
        VPNPlugin().register(to: registry)
        QuickActionsPlugin().register(to: registry)
    }
}
