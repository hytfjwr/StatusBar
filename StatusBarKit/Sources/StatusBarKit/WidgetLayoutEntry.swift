import Foundation

/// Persisted layout state for a single widget.
public struct WidgetLayoutEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var section: WidgetPosition
    public var sortIndex: Int
    public var isVisible: Bool

    public init(id: String, section: WidgetPosition, sortIndex: Int, isVisible: Bool = true) {
        self.id = id
        self.section = section
        self.sortIndex = sortIndex
        self.isVisible = isVisible
    }
}
