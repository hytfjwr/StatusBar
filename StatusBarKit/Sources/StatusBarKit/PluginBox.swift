/// Bridge type for safely creating @MainActor plugins from nonisolated @_cdecl factory functions.
///
/// Plugin authors use this in their factory function:
/// ```swift
/// @_cdecl("createStatusBarPlugin")
/// public func createStatusBarPlugin() -> UnsafeMutableRawPointer {
///     let box = PluginBox { MyPlugin() }
///     return Unmanaged.passRetained(box).toOpaque()
/// }
/// ```
///
/// The host calls `box.factory()` on the main actor to safely instantiate the plugin.
public final class PluginBox: @unchecked Sendable {
    /// A closure that creates the plugin. Must be called on @MainActor.
    public let factory: @MainActor () -> any StatusBarPlugin

    public init(_ factory: @escaping @MainActor () -> any StatusBarPlugin) {
        self.factory = factory
    }
}
