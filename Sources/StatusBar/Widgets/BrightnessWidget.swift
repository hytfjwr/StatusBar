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

/// Throttle window for DDC writes during slider drag. DDC writes take 30-80ms
/// per packet; without coalescing, a fast drag overruns the I2C bus and the
/// monitor visibly lags. 40ms still feels live to the user.
private let ddcWriteDebounce: Duration = .milliseconds(40)

private func brightnessIconName(for value: Float) -> String {
    switch value {
    case ..<0.34: "sun.min"
    case ..<0.67: "sun.max"
    default: "sun.max.fill"
    }
}

private func brightnessPercent(_ value: Float) -> Int {
    Int((value * 100).rounded())
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

    // DDC slider coalescing: the slider's onChange fires per pixel, but we only
    // want to push one write per ddcWriteDebounce. While a flush task is in
    // flight, additional drags overwrite `pendingDDCWrites[id]` instead of
    // queueing more I/O.
    private var pendingDDCWrites: [CGDirectDisplayID: Float] = [:]
    private var ddcFlushTask: Task<Void, Never>?

    private let service = BrightnessService.shared

    func start() {
        guard timer == nil, service.isAvailable, let interval = updateInterval else {
            return
        }
        Task { @MainActor in
            await refreshDisplays()
        }
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
                await self?.refreshDisplays()
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
        ddcFlushTask?.cancel()
        ddcFlushTask = nil
        pendingDDCWrites.removeAll()
        popupPanel?.hidePopup()
    }

    func body() -> some View {
        BrightnessBarBody(displays: displays) { [weak self] in
            self?.togglePopup()
        }
    }

    // MARK: - Polling

    private func refreshDisplays() async {
        // Topology changed (or first scan) — drop any cached IOAVService handles
        // before re-enumerating so we don't read from a stale I2C transport.
        await service.invalidateExternalCache()
        let fresh = await service.enumerateDisplays()
        let topologyChanged = Set(displays.map(\.id)) != Set(fresh.map(\.id))
        withAnimation(.numericTransition) {
            displays = fresh
        }
        if topologyChanged {
            lastEmitted = lastEmitted.filter { key, _ in fresh.contains { $0.id == key } }
            pendingDDCWrites = pendingDDCWrites.filter { key, _ in fresh.contains { $0.id == key } }
            if popupPanel?.isVisible == true {
                refreshPopup()
            }
        }
    }

    private func poll() {
        let snapshot = displays.map { (id: $0.id, kind: $0.kind) }
        Task { @MainActor in
            var newValues: [CGDirectDisplayID: Float] = [:]
            for entry in snapshot {
                if let value = await service.getBrightness(entry.id, kind: entry.kind) {
                    newValues[entry.id] = value
                }
            }
            guard !newValues.isEmpty else {
                return
            }
            var updated = displays
            var changed = false
            for index in updated.indices {
                guard let value = newValues[updated[index].id] else {
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
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else {
            return
        }
        let kind = displays[index].kind
        displays[index].brightness = value
        emitIfChanged(displayID: displayID, value: value)

        switch kind {
        case .builtin,
             .displayServicesExternal:
            Task { @MainActor in
                _ = await service.setBrightness(value, for: displayID, kind: kind)
            }
        case .ddc:
            pendingDDCWrites[displayID] = value
            scheduleDDCFlush()
        }
    }

    private func scheduleDDCFlush() {
        guard ddcFlushTask == nil else {
            return
        }
        ddcFlushTask = Task { @MainActor in
            try? await Task.sleep(for: ddcWriteDebounce)
            let snapshot = pendingDDCWrites
            pendingDDCWrites.removeAll()
            ddcFlushTask = nil
            for (id, value) in snapshot {
                _ = await service.setBrightness(value, for: id, kind: .ddc)
            }
        }
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

// MARK: - BrightnessBarBody

/// Renders the bar entry for whichever display this bar instance lives on.
/// `screenIndex` is injected by `BarContentView` for each per-screen bar window,
/// so a multi-display setup ends up showing each display's own brightness in
/// its own bar.
private struct BrightnessBarBody: View {
    let displays: [ManagedDisplay]
    let onTap: () -> Void
    @Environment(\.screenIndex) private var screenIndex

    var body: some View {
        Group {
            if let display = currentDisplay {
                HStack(spacing: 2) {
                    Image(systemName: brightnessIconName(for: display.brightness))
                        .font(Theme.sfIconFont)
                        .foregroundStyle(.primary)
                        .frame(width: 18, alignment: .center)
                    Text("\(brightnessPercent(display.brightness))%")
                        .font(Theme.labelFont)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .frame(width: 38, alignment: .trailing)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(display.name)
                .accessibilityValue("\(brightnessPercent(display.brightness))%")
            } else {
                EmptyView()
            }
        }
    }

    private var currentDisplay: ManagedDisplay? {
        let screens = NSScreen.screens
        guard screenIndex < screens.count else {
            return nil
        }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let id = screens[screenIndex].deviceDescription[key] as? CGDirectDisplayID else {
            return nil
        }
        // Mirror secondary IDs aren't enumerated into `displays`; resolve to the
        // primary so the bar still shows a value when the user mirrors.
        var lookupID = id
        if CGDisplayIsInMirrorSet(id) != 0 {
            let primary = CGDisplayMirrorsDisplay(id)
            if primary != 0 {
                lookupID = primary
            }
        }
        return displays.first(where: { $0.id == lookupID })
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
