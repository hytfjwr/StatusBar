import Foundation

/// Metadata describing a plugin.
public struct PluginManifest: Sendable {
    /// Unique identifier (e.g. "com.statusbar.aerospace").
    public let id: String

    /// Human-readable name.
    public let name: String

    /// Plugin version string.
    public let version: String

    public init(id: String, name: String, version: String = "1.0.0") {
        self.id = id
        self.name = name
        self.version = version
    }
}
