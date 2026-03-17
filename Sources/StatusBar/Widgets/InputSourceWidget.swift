import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class InputSourceWidget: StatusBarWidget {
    let id = "input-source"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String { "keyboard" }

    private var abbreviation = "??"
    private var service: InputSourceService?

    func start() {
        service = InputSourceService { [weak self] in
            self?.refresh()
        }
        service?.start()
        refresh()
    }

    func stop() {
        service?.stop()
        service = nil
    }

    private func refresh() {
        abbreviation = service?.currentSourceAbbreviation() ?? "??"
    }

    func body() -> some View {
        Text(abbreviation)
            .font(Theme.smallFont)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: .rect(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { [weak self] in
                self?.service?.cycleToNextSource()
            }
    }
}
