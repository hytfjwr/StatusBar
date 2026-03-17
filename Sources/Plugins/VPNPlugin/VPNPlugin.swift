import StatusBarKit

@MainActor
public struct VPNPlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.statusbar.vpn",
        name: "VPN"
    )

    public let widgets: [any StatusBarWidget]

    public init() {
        widgets = [VPNWidget()]
    }
}
