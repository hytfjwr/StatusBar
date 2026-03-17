import SwiftUI
import StatusBarKit

@MainActor
@Observable
final class ChevronWidget: StatusBarWidget {
    let id = "chevron"
    let position: WidgetPosition = .left
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String { "chevron.right" }

    func start() {}
    func stop() {}

    func body() -> some View {
        Image(systemName: "chevron.right")
            .font(Theme.smallFont)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
    }
}
