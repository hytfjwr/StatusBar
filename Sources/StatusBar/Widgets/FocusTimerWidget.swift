import Combine
import StatusBarKit
import SwiftUI

// MARK: - FocusTimerWidget

@MainActor
@Observable
final class FocusTimerWidget: StatusBarWidget {
    let id = "focus-timer"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 2
    var sfSymbolName: String { "timer" }

    private var timer: AnyCancellable?
    private var popupPanel: PopupPanel?

    enum TimerState {
        case idle
        case running(mode: String, endTime: Date)
        case completed(at: Date)
    }

    private var state: TimerState = .idle
    private var displayText = "--:--"
    private var displayColor: Color = Theme.secondary
    private var bounceCounter = 0
    private var showCustomSlider = false
    private var customMinutes: Double = 25

    func start() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    func stop() {
        timer?.cancel()
        popupPanel?.hidePopup()
    }

    func startTimer(mode: String, duration: TimeInterval) {
        state = .running(mode: mode, endTime: Date().addingTimeInterval(duration))
        bounceCounter += 1
        NSSound(named: "Tink")?.play()
        update()
        refreshPopup()
    }

    func stopTimer() {
        state = .idle
        displayText = "--:--"
        displayColor = Theme.secondary
        NSSound(named: "Purr")?.play()
        refreshPopup()
    }

    func toggleCustomSlider() {
        showCustomSlider.toggle()
        NSSound(named: "Pop")?.play()
        refreshPopup()
    }

    func setCustomMinutes(_ value: Double) {
        customMinutes = value
    }

    private func refreshPopup() {
        popupPanel?.updateContent(makePopupContent())
        popupPanel?.resizeToFitContent()
    }

    private func makePopupContent() -> FocusTimerPopupContent {
        FocusTimerPopupContent(
            widget: self,
            showCustomSlider: showCustomSlider,
            customMinutes: customMinutes
        )
    }

    private func update() {
        switch state {
        case .idle:
            displayText = "--:--"
            displayColor = Theme.secondary

        case let .running(_, endTime):
            let remaining = endTime.timeIntervalSinceNow
            if remaining <= 0 {
                state = .completed(at: Date())
                displayText = "Done"
                displayColor = Theme.green
                NSSound(named: "Glass")?.play()
                return
            }

            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            displayText = String(format: "%02d:%02d", minutes, seconds)

            if remaining <= 300 {
                displayColor = Theme.yellow
            } else {
                displayColor = Theme.primary
            }

        case let .completed(at):
            if Date().timeIntervalSince(at) >= 3 {
                state = .idle
                displayText = "--:--"
                displayColor = Theme.secondary
            }
        }
    }

    func body() -> some View {
        HStack(spacing: 5) {
            Image(systemName: timerSFSymbol)
                .font(Theme.sfIconFont)
                .foregroundColor(displayColor)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: bounceCounter)
            Text(displayText)
                .font(Theme.monoFont)
                .foregroundColor(displayColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { [weak self] in
            self?.togglePopup()
        }
    }

    private var timerSFSymbol: String {
        switch state {
        case .idle: "timer"
        case .running: "timer"
        case .completed: "checkmark.circle.fill"
        }
    }

    private func togglePopup() {
        if popupPanel?.isVisible == true {
            popupPanel?.hidePopup()
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        if popupPanel == nil {
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame(width: 80) else {
            return
        }

        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: makePopupContent())
    }
}

// MARK: - FocusTimerPopupContent

struct FocusTimerPopupContent: View {
    let widget: FocusTimerWidget
    let showCustomSlider: Bool
    let customMinutes: Double

    @State private var rippleTrigger = 0
    @State private var sliderValue: Double

    init(widget: FocusTimerWidget, showCustomSlider: Bool, customMinutes: Double) {
        self.widget = widget
        self.showCustomSlider = showCustomSlider
        self.customMinutes = customMinutes
        self._sliderValue = State(initialValue: customMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Presets")

            VStack(spacing: 2) {
                PopupRow(icon: "laptopcomputer", iconColor: .blue, label: "Coding") {
                    Text("50 min")
                        .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary)
                } action: {
                    widget.startTimer(mode: "Coding", duration: 3_000)
                }
                PopupRow(icon: "eye", iconColor: .cyan, label: "Review") {
                    Text("20 min")
                        .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary)
                } action: {
                    widget.startTimer(mode: "Review", duration: 1_200)
                }
                PopupRow(icon: "cup.and.saucer.fill", iconColor: .green, label: "Break") {
                    Text("10 min")
                        .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary)
                } action: {
                    widget.startTimer(mode: "Break", duration: 600)
                }
                PopupRow(
                    icon: "slider.horizontal.3",
                    iconColor: .purple,
                    label: "Custom"
                ) {
                    Image(systemName: showCustomSlider ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                } action: {
                    widget.toggleCustomSlider()
                }

                // Custom slider
                if showCustomSlider {
                    VStack(spacing: 8) {
                        HStack {
                            Text("\(Int(sliderValue)) min")
                                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        Slider(value: $sliderValue, in: 1...120, step: 1)
                            .tint(.purple)
                            .onChange(of: sliderValue) { _, newValue in
                                widget.setCustomMinutes(newValue)
                            }

                        HStack {
                            Text("1 min")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("120 min")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            rippleTrigger += 1
                            widget.startTimer(mode: "Custom", duration: sliderValue * 60)
                        } label: {
                            Text("Start")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(ScalePressButtonStyle())
                        .modifier(RippleEffect(trigger: rippleTrigger, color: .purple))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 6)

            PopupDivider()

            VStack(spacing: 2) {
                PopupRow(icon: "stop.fill", iconColor: Theme.red, label: "Stop Timer") {
                    widget.stopTimer()
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 230)
    }
}

// MARK: - ScalePressButtonStyle

private struct ScalePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

// MARK: - RippleEffect

private struct RippleEffect: ViewModifier {
    var trigger: Int
    var color: Color

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Ripple(), trigger: trigger) { content, value in
                content.overlay {
                    ZStack {
                        Circle()
                            .stroke(color.opacity(value.opacity1), lineWidth: 2)
                            .scaleEffect(value.scale1)
                        Circle()
                            .stroke(color.opacity(value.opacity2), lineWidth: 1.5)
                            .scaleEffect(value.scale2)
                    }
                    .allowsHitTesting(false)
                }
            } keyframes: { _ in
                KeyframeTrack(\.scale1) {
                    CubicKeyframe(2.5, duration: 0.6)
                }
                KeyframeTrack(\.opacity1) {
                    CubicKeyframe(0.6, duration: 0.05)
                    CubicKeyframe(0, duration: 0.55)
                }
                KeyframeTrack(\.scale2) {
                    LinearKeyframe(0, duration: 0.12)
                    CubicKeyframe(2.0, duration: 0.55)
                }
                KeyframeTrack(\.opacity2) {
                    LinearKeyframe(0, duration: 0.12)
                    CubicKeyframe(0.4, duration: 0.05)
                    CubicKeyframe(0, duration: 0.5)
                }
            }
    }

    private struct Ripple {
        var scale1: CGFloat = 0
        var opacity1: Double = 0
        var scale2: CGFloat = 0
        var opacity2: Double = 0
    }
}
