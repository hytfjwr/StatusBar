import StatusBarKit
import SwiftUI

@MainActor
@Observable
public final class QuickActionsWidget: StatusBarWidget {
    public let id = "quick-actions"
    public let position: WidgetPosition = .left
    public let updateInterval: TimeInterval? = nil
    public var sfSymbolName: String { "bolt.fill" }

    private var popupPanel: PopupPanel?

    public init() {}

    public func start() {}
    public func stop() {
        popupPanel?.hidePopup()
    }

    public func body() -> some View {
        Image(systemName: "wrench.and.screwdriver")
            .font(Theme.sfIconFont)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 2)
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
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 200))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }

        let content = QuickActionsPopupContent { [weak self] in
            self?.popupPanel?.hidePopup()
        }

        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }
}

// MARK: - QuickActionsPopupContent

struct QuickActionsPopupContent: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopupSectionHeader("Quick Actions")

            VStack(spacing: 2) {
                PopupRow(icon: "macwindow.on.rectangle", label: "Fix Windows") {
                    Task { try? await ShellCommand.run("~/.local/bin/aerospace-fix-windows --quiet") }
                    dismiss()
                }
                PopupRow(icon: "cup.and.saucer", label: "Awake") {
                    Task { try? await ShellCommand.run("~/.local/bin/awake toggle") }
                    dismiss()
                }
                PopupRow(icon: "trash", label: "Clean Neovim Cache") {
                    Task { try? await ShellCommand.run("~/.local/bin/nvim-clean") }
                    dismiss()
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 230)
    }
}
