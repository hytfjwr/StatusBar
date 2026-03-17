import SwiftUI

/// Protocol for widget registration and querying.
/// Plugins can reference the registry through this protocol
/// without depending on the app target.
@MainActor
public protocol WidgetRegistryProtocol: AnyObject {
    func register(_ widget: any StatusBarWidget)
    func widgets(for position: WidgetPosition) -> [AnyStatusBarWidget]
}
