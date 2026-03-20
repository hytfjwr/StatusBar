import StatusBarKit
import SwiftUI

// MARK: - AppleMenuWidget

@MainActor
@Observable
final class AppleMenuWidget: StatusBarWidget {
    let id = "apple-menu"
    let position: WidgetPosition = .left
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String {
        "apple.logo"
    }

    private var popupPanel: PopupPanel?

    func start() {}
    func stop() {
        popupPanel?.hidePopup()
    }

    func body() -> some View {
        Image(systemName: "apple.logo")
            .font(Theme.sfIconFont)
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture { [weak self] in
                self?.togglePopup()
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
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 300))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }

        let content = AppleMenuPopupContent { [weak self] in
            self?.popupPanel?.hidePopup()
        }

        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }
}

// MARK: - AppleMenuPopupContent

struct AppleMenuPopupContent: View {
    let dismiss: () -> Void

    @State private var confirmAction: SystemAction?

    private enum SystemAction: String, Identifiable {
        case lockScreen = "Lock Screen"
        case sleep = "Sleep"
        case restart = "Restart"
        case shutdown = "Shutdown"

        var id: String {
            rawValue
        }

        var command: String {
            switch self {
            case .lockScreen: "pmset displaysleepnow"
            case .sleep: "osascript -e 'tell application \"System Events\" to sleep'"
            case .restart: "osascript -e 'tell application \"System Events\" to restart'"
            case .shutdown: "osascript -e 'tell application \"System Events\" to shut down'"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = confirmAction {
                // Inline confirmation dialog
                VStack(spacing: 12) {
                    Text(action.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Are you sure you want to \(action.rawValue.lowercased())?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                confirmAction = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button(action.rawValue) {
                            Task { try? await ShellCommand.run(action.command) }
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.red)
                        .controlSize(.regular)
                    }
                }
                .padding(20)
            } else {
                // System section
                PopupSectionHeader("System")

                VStack(spacing: 2) {
                    PopupRow(icon: "gearshape", label: "Preferences") {
                        PreferencesWindow.shared.show()
                        dismiss()
                    }
                    PopupRow(icon: "gearshape.2", label: "System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:") {
                            NSWorkspace.shared.open(url)
                        }
                        dismiss()
                    }
                    PopupRow(icon: "lock.display", label: "Lock Screen") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            confirmAction = .lockScreen
                        }
                    }
                    PopupRow(icon: "moon.fill", label: "Sleep") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            confirmAction = .sleep
                        }
                    }
                    PopupRow(icon: "arrow.triangle.2.circlepath", label: "Restart") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            confirmAction = .restart
                        }
                    }
                    PopupRow(icon: "power", iconColor: Theme.red, label: "Shutdown") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            confirmAction = .shutdown
                        }
                    }
                }
                .padding(.horizontal, 6)

                PopupDivider()

                // Utilities section
                PopupSectionHeader("Utilities")

                VStack(spacing: 2) {
                    PopupRow(icon: "arrow.clockwise", label: "Reload") {
                        AppUpdateService.relaunchApp()
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 230)
    }
}
