import Foundation

// MARK: - MonitorMatchRule

/// A single monitor-specific configuration rule in config.yml.
/// `match` is compared against `NSScreen.localizedName` as a case-insensitive substring.
/// The special value `"*"` matches any screen (use as a fallback).
struct MonitorMatchRule: Codable, Equatable {
    var match: String
    var autoHide: Bool?
    /// Widget IDs to show on this monitor. `nil` means show all widgets.
    /// An empty array `[]` means show no widgets.
    var widgets: [String]?
}

// MARK: - MonitorConfig

/// Resolved per-monitor configuration with concrete values (no optionals).
struct MonitorConfig: Equatable {
    let autoHide: Bool
    /// Widget IDs to show. `nil` means no filtering (show all).
    let widgetFilter: Set<String>?
}
