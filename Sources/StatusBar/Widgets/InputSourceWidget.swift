import StatusBarKit
import SwiftUI

// MARK: - InputSourceEvent

enum InputSourceEvent {
    static let changed = "input_source_changed"
}

extension IPCEventEnvelope {
    static func inputSourceChanged(abbreviation: String) -> Self {
        IPCEventEnvelope(
            event: InputSourceEvent.changed,
            payload: .object(["abbreviation": .string(abbreviation)])
        )
    }
}

// MARK: - InputSourceWidget

@MainActor
@Observable
final class InputSourceWidget: StatusBarWidget, EventEmitting {
    let id = "input-source"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String {
        "keyboard"
    }

    private var abbreviation = "??"
    private var lastEmittedAbbreviation = ""
    private var service: InputSourceService?

    func start() {
        guard service == nil else {
            return
        }
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
        if abbreviation != lastEmittedAbbreviation {
            lastEmittedAbbreviation = abbreviation
            emit(.inputSourceChanged(abbreviation: abbreviation))
        }
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Input Source")
            .accessibilityValue(abbreviation)
    }
}
