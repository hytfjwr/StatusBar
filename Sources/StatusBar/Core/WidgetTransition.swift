import SwiftUI

extension Animation {
    static let widgetTransition: Animation = .spring(duration: 0.3, bounce: 0.15)
}

extension AnyTransition {
    /// Slide + fade: width expands from zero on the leading edge, opacity 0→1.
    @MainActor static let widgetAppear: AnyTransition = .modifier(
        active: WidgetInsertModifier(progress: 0),
        identity: WidgetInsertModifier(progress: 1)
    )
}

// MARK: - WidgetInsertModifier

private struct WidgetInsertModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(x: progress, y: 1, anchor: .leading)
            .clipped()
    }
}
