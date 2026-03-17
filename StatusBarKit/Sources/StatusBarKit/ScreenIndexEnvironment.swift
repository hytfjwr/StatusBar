import SwiftUI

// MARK: - ScreenIndexKey

private struct ScreenIndexKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

public extension EnvironmentValues {
    var screenIndex: Int {
        get { self[ScreenIndexKey.self] }
        set { self[ScreenIndexKey.self] = newValue }
    }
}
