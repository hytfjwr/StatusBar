import SwiftUI
import StatusBarKit

// MARK: - AppleMenuWidget

@MainActor
@Observable
final class AppleMenuWidget: StatusBarWidget {
    let id = "apple-menu"
    let position: WidgetPosition = .left
    let updateInterval: TimeInterval? = nil
    var sfSymbolName: String { "apple.logo" }

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

    var body: some View {
        VStack(spacing: 0) {
            // System section
            PopupSectionHeader("System")

            VStack(spacing: 2) {
                PopupRow(icon: "gearshape", label: "Preferences") {
                    PreferencesWindow.shared.show()
                    dismiss()
                }
                PopupRow(icon: "lock.display", label: "Lock Screen") {
                    Task { try? await ShellCommand.run("pmset displaysleepnow") }
                    dismiss()
                }
                PopupRow(icon: "moon.fill", label: "Sleep") {
                    Task { try? await ShellCommand.run("osascript -e 'tell application \"System Events\" to sleep'") }
                    dismiss()
                }
                PopupRow(icon: "arrow.triangle.2.circlepath", label: "Restart") {
                    Task { try? await ShellCommand.run("osascript -e 'tell application \"System Events\" to restart'") }
                    dismiss()
                }
                PopupRow(icon: "power", iconColor: Theme.red, label: "Shutdown") {
                    Task { try? await ShellCommand.run("osascript -e 'tell application \"System Events\" to shut down'") }
                    dismiss()
                }
            }
            .padding(.horizontal, 6)

            PopupDivider()

            // Utilities section
            PopupSectionHeader("Utilities")

            VStack(spacing: 2) {
                PopupRow(icon: "arrow.clockwise", label: "Reload") {
                    let relaunchCmd: String
                    if Bundle.main.bundleURL.pathExtension == "app" {
                        relaunchCmd = "open \"\(Bundle.main.bundleURL.path)\""
                    } else {
                        relaunchCmd = "\"\(Bundle.main.executablePath ?? "")\" &"
                    }
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/bin/sh")
                    task.arguments = ["-c", "sleep 0.5 && \(relaunchCmd)"]
                    try? task.run()
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 230)
    }
}
