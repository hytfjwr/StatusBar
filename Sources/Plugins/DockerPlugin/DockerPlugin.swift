import StatusBarKit

@MainActor
public struct DockerPlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.statusbar.docker",
        name: "Docker"
    )

    public let widgets: [any StatusBarWidget]

    public init() {
        widgets = [DockerWidget()]
    }
}
