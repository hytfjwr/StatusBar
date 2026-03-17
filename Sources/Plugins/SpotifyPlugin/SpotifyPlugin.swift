import StatusBarKit

@MainActor
public struct SpotifyPlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.statusbar.spotify",
        name: "Spotify"
    )

    public let widgets: [any StatusBarWidget]

    public init() {
        widgets = [SpotifyWidget()]
    }
}
