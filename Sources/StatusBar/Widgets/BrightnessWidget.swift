import AppKit
import Combine
import CoreGraphics
import StatusBarKit
import SwiftUI

// MARK: - BrightnessEvent

enum BrightnessEvent {
    static let changed = "brightness_changed"
}

extension IPCEventEnvelope {
    static func brightnessChanged(displayID: CGDirectDisplayID, brightness: Float) -> Self {
        IPCEventEnvelope(
            event: BrightnessEvent.changed,
            payload: .object([
                "displayID": .number(Double(displayID)),
                "brightness": .number(Double(brightness)),
            ])
        )
    }
}

// MARK: - Shared helpers

/// Threshold below which a brightness delta is considered noise.
/// Sub-1% changes don't move the displayed integer percentage.
private let brightnessEpsilon: Float = 0.005

private func brightnessIconName(for value: Float) -> String {
    switch value {
    case ..<0.34: "sun.min"
    case ..<0.67: "sun.max"
    default: "sun.max.fill"
    }
}

// MARK: - BrightnessWidget

@MainActor
@Observable
final class BrightnessWidget: StatusBarWidget, EventEmitting {
    let id = "brightness"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2.0
    var sfSymbolName: String {
        "sun.max"
    }

    private var displays: [ManagedDisplay] = []
    private var timer: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var popupPanel: PopupPanel?
    private var lastEmitted: [CGDirectDisplayID: Float] = [:]

    private let service = BrightnessService.shared

    func start() {
        guard timer == nil, service.isAvailable, let interval = updateInterval else {
            return
        }
        refreshDisplays()
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        popupPanel?.hidePopup()
    }

    func body() -> some View {
        Group {
            if displays.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 2) {
                    Image(systemName: brightnessIconName(for: barBrightness))
                        .font(Theme.sfIconFont)
                        .foregroundStyle(.primary)
                        .frame(width: 18, alignment: .center)
                    Text("\(percent(barBrightness))%")
                        .font(Theme.labelFont)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .frame(width: 38, alignment: .trailing)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { [weak self] in
                    self?.togglePopup()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Brightness")
                .accessibilityValue("\(percent(barBrightness))%")
            }
        }
    }

    // MARK: - Polling

    private func refreshDisplays() {
        let fresh = service.enumerateDisplays()
        let topologyChanged = Set(displays.map(\.id)) != Set(fresh.map(\.id))
        withAnimation(.numericTransition) {
            displays = fresh
        }
        if topologyChanged {
            lastEmitted = lastEmitted.filter { key, _ in fresh.contains { $0.id == key } }
            if popupPanel?.isVisible == true {
                refreshPopup()
            }
        }
    }

    private func poll() {
        var changed = false
        var updated = displays
        for index in updated.indices {
            guard let value = service.getBrightness(updated[index].id) else {
                continue
            }
            if abs(updated[index].brightness - value) >= brightnessEpsilon {
                updated[index].brightness = value
                changed = true
            }
        }
        guard changed else {
            return
        }
        withAnimation(.numericTransition) {
            displays = updated
        }
        emitChanges()
        if popupPanel?.isVisible == true {
            refreshPopup()
        }
    }

    private func emitChanges() {
        for display in displays {
            emitIfChanged(displayID: display.id, value: display.brightness)
        }
    }

    private func emitIfChanged(displayID: CGDirectDisplayID, value: Float) {
        if let last = lastEmitted[displayID], abs(last - value) < brightnessEpsilon {
            return
        }
        lastEmitted[displayID] = value
        emit(.brightnessChanged(displayID: displayID, brightness: value))
    }

    // MARK: - Slider write-through

    private func applyBrightness(_ value: Float, to displayID: CGDirectDisplayID) {
        guard service.setBrightness(value, for: displayID) else {
            return
        }
        if let index = displays.firstIndex(where: { $0.id == displayID }) {
            displays[index].brightness = value
        }
        emitIfChanged(displayID: displayID, value: value)
    }

    // MARK: - Bar display

    private var barBrightness: Float {
        let mainID = CGMainDisplayID()
        if let main = displays.first(where: { $0.id == mainID }) {
            return main.brightness
        }
        return displays.first?.brightness ?? 0
    }

    private func percent(_ value: Float) -> Int {
        Int((value * 100).rounded())
    }

    // MARK: - Popup

    private func togglePopup() {
        if popupPanel?.isVisible == true {
            popupPanel?.hidePopup()
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        if popupPanel == nil {
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 140))
        }
        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: popupContent())
    }

    private func refreshPopup() {
        guard let panel = popupPanel, panel.isVisible else {
            return
        }
        panel.updateContent(popupContent())
        panel.resizeToFitContent()
    }

    private func popupContent() -> some View {
        BrightnessPopupContent(
            displays: displays,
            onChange: { [weak self] displayID, value in
                self?.applyBrightness(value, to: displayID)
            }
        )
    }
}

// MARK: - BrightnessPopupContent

private struct BrightnessPopupContent: View {
    let displays: [ManagedDisplay]
    let onChange: (CGDirectDisplayID, Float) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Brightness")

            VStack(spacing: 10) {
                ForEach(displays) { display in
                    BrightnessDisplayRow(
                        display: display,
                        onChange: { onChange(display.id, $0) }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 300)
    }
}

// MARK: - BrightnessDisplayRow

private struct BrightnessDisplayRow: View {
    let display: ManagedDisplay
    let onChange: (Float) -> Void

    @State private var sliderValue: Double
    @State private var isEditing: Bool = false

    init(display: ManagedDisplay, onChange: @escaping (Float) -> Void) {
        self.display = display
        self.onChange = onChange
        _sliderValue = State(initialValue: Double(display.brightness * 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display.name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Image(systemName: brightnessIconName(for: Float(sliderValue / 100)))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 22, alignment: .center)
                    .symbolRenderingMode(.hierarchical)

                Slider(value: $sliderValue, in: 0 ... 100, step: 1) { editing in
                    isEditing = editing
                }
                .tint(.blue)
                .focusable(false)
                .onChange(of: sliderValue) { _, newValue in
                    onChange(Float(newValue / 100))
                }

                Text("\(Int(sliderValue))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .onChange(of: display.brightness) { _, newValue in
            // External updates (e.g. F1/F2 polling tick) must not fight the user's drag.
            guard !isEditing else {
                return
            }
            let next = Double(newValue * 100)
            if abs(sliderValue - next) >= 1 {
                sliderValue = next
            }
        }
    }
}
