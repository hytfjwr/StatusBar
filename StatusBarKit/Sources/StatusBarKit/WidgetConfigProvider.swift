import Foundation

// MARK: - ConfigValue

/// A type-erased value for widget configuration. Encodes/decodes as a raw YAML scalar.
public enum ConfigValue: Codable, Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Order matters: Bool before Int (YAML `true`/`false`), Int before Double
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported config value type"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        }
    }

    // Convenience accessors
    public var stringValue: String? {
        if case .string(let v) = self { return v } else { return nil }
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v } else { return nil }
    }

    public var intValue: Int? {
        if case .int(let v) = self { return v } else { return nil }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
}

// MARK: - WidgetConfigProvider

/// Protocol for widget settings that can be persisted to the YAML config file.
/// Each widget's Settings class conforms to this and registers with `WidgetConfigRegistry`.
@MainActor
public protocol WidgetConfigProvider: AnyObject {
    /// The widget ID used as the key in the YAML `widgetSettings` section.
    var configID: String { get }
    /// Export current settings as a flat dictionary.
    func exportConfig() -> [String: ConfigValue]
    /// Apply settings from a dictionary (hot-reload or initial load).
    func applyConfig(_ values: [String: ConfigValue])
}

// MARK: - WidgetConfigRegistry

/// Central registry for widget config providers. Lives in StatusBarKit so both
/// built-in widgets and plugins can register without importing the app target.
@MainActor
public final class WidgetConfigRegistry {
    public static let shared = WidgetConfigRegistry()

    /// Raw config data loaded from YAML, keyed by widget ID.
    private var loadedConfig: [String: [String: ConfigValue]] = [:]

    /// Registered providers for live widgets.
    private var providers: [String: WidgetConfigProvider] = [:]

    /// Callback invoked when a widget setting changes. Set by ConfigLoader.
    public var onSettingsChanged: (@MainActor () -> Void)?

    private init() {}

    /// Store loaded YAML widget settings. Called by ConfigLoader during bootstrap.
    public func setLoadedConfig(_ config: [String: [String: ConfigValue]]) {
        loadedConfig = config
    }

    /// Get config values for a widget. Called by Settings singletons in `init()`.
    public func values(for widgetID: String) -> [String: ConfigValue]? {
        loadedConfig[widgetID]
    }

    /// Register a settings provider. Called by each Settings singleton in `init()`.
    public func register(_ provider: WidgetConfigProvider) {
        providers[provider.configID] = provider
    }

    /// Apply loaded config to all registered providers (hot-reload).
    public func applyToAll() {
        for (id, provider) in providers {
            if let values = loadedConfig[id] {
                provider.applyConfig(values)
            }
        }
    }

    /// Export current settings from all registered providers.
    public func exportAll() -> [String: [String: ConfigValue]] {
        var result = loadedConfig
        for (id, provider) in providers {
            result[id] = provider.exportConfig()
        }
        return result
    }

    /// Notify that a widget setting changed (triggers YAML write-back).
    public func notifySettingsChanged() {
        onSettingsChanged?()
    }
}
