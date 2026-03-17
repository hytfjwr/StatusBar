import Foundation

/// On-disk manifest for a dynamically loaded plugin bundle (.statusplugin).
/// Read from manifest.json inside each plugin bundle directory.
public struct DylibPluginManifest: Codable, Sendable {
    /// Unique identifier (reverse-domain, e.g. "com.example.weather").
    public let id: String

    /// Human-readable display name.
    public let name: String

    /// Plugin version (semver).
    public let version: String

    /// The StatusBarKit version this plugin was built against.
    /// Used for compatibility checking with semantic versioning.
    public let statusBarKitVersion: String

    /// The Swift compiler version used to build this plugin.
    public let swiftVersion: String

    /// The C symbol name to look up via dlsym. Defaults to "createStatusBarPlugin".
    public let entrySymbol: String

    /// Optional description.
    public let description: String?

    /// Optional author name.
    public let author: String?

    /// Optional homepage URL (e.g. GitHub repo).
    public let homepage: String?

    /// Optional SHA-256 hash of the dylib for integrity verification.
    public let sha256: String?

    public init(
        id: String,
        name: String,
        version: String,
        statusBarKitVersion: String,
        swiftVersion: String,
        entrySymbol: String = "createStatusBarPlugin",
        description: String? = nil,
        author: String? = nil,
        homepage: String? = nil,
        sha256: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.statusBarKitVersion = statusBarKitVersion
        self.swiftVersion = swiftVersion
        self.entrySymbol = entrySymbol
        self.description = description
        self.author = author
        self.homepage = homepage
        self.sha256 = sha256
    }
}

// MARK: - Semantic Version Parsing

/// Minimal semver representation for compatibility checks.
public struct SemanticVersion: Sendable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        self.major = parts[0]
        self.minor = parts[1]
        self.patch = parts.count >= 3 ? parts[2] : 0
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Check if a plugin built against `pluginVersion` is compatible with this (host) version.
    /// Rules:
    /// - Major version must match exactly
    /// - Plugin's minor version must be ≤ host's minor version
    ///   (plugin may use APIs added in its minor version)
    public func isCompatible(with pluginVersion: SemanticVersion) -> Bool {
        guard major == pluginVersion.major else { return false }
        return pluginVersion.minor <= minor
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
