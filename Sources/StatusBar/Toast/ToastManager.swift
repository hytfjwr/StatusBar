import AppKit
import StatusBarKit

@MainActor
@Observable
final class ToastManager {
    static let shared = ToastManager()

    private(set) var toasts: [ToastItem] = []
    /// Monotonically increasing counter; bumped on add/remove only.
    /// Used as animation value to avoid array allocation per render.
    private(set) var layoutVersion: Int = 0
    private var dismissTasks: [String: Task<Void, any Error>] = [:]
    private let maxVisible = 4

    private var panel: ToastTrayPanel?
    private weak var anchorWindow: BarWindow?
    private weak var anchorScreen: NSScreen?

    private init() {}

    // MARK: - Setup

    func reposition(anchoredTo barWindow: BarWindow, on screen: NSScreen) {
        anchorWindow = barWindow
        anchorScreen = screen
        repositionPanel()
    }

    // MARK: - Post

    @discardableResult
    func post(_ request: ToastRequest, action: (@MainActor () -> Void)? = nil) -> String {
        let resolvedAction = action ?? resolveShellAction(request.actionShellCommand)

        let item = ToastItem(
            request: request,
            action: resolvedAction
        )

        // Evict oldest if at capacity (without repositioning per eviction)
        while toasts.count >= maxVisible {
            evict(id: toasts[0].id)
        }

        toasts.append(item)
        layoutVersion += 1
        scheduleDismiss(for: item)
        showPanel()
        repositionPanel()

        return item.id
    }

    // MARK: - Dismiss

    func dismiss(id: String) {
        cancelDismissTask(for: id)

        guard let index = toasts.firstIndex(where: { $0.id == id }) else {
            return
        }
        toasts.remove(at: index)
        layoutVersion += 1

        if toasts.isEmpty {
            hidePanel()
        } else {
            repositionPanel()
        }
    }

    func dismissAll() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()
        toasts.removeAll()
        layoutVersion += 1
        hidePanel()
    }

    // MARK: - Progress

    func updateProgress(id: String, value: Double) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else {
            return
        }
        toasts[index].progress = min(max(value, 0), 1)
    }

    func updateTint() {
        panel?.updateTint()
    }

    // MARK: - Private

    /// Remove a toast without repositioning. Used during batch eviction.
    private func evict(id: String) {
        cancelDismissTask(for: id)
        guard let index = toasts.firstIndex(where: { $0.id == id }) else {
            return
        }
        toasts.remove(at: index)
    }

    private func cancelDismissTask(for id: String) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }

    private func resolveShellAction(_ command: String?) -> (@MainActor () -> Void)? {
        guard let command else {
            return nil
        }
        return {
            Task.detached {
                try? await ShellCommand.run(command)
            }
        }
    }

    private func scheduleDismiss(for item: ToastItem) {
        guard item.request.duration > 0 else {
            return
        }
        let id = item.id
        dismissTasks[id] = Task { [weak self] in
            try await Task.sleep(for: .seconds(item.request.duration))
            self?.dismiss(id: id)
        }
    }

    private static let scaleUp: CGFloat = 1.08

    private func showPanel() {
        guard panel == nil, anchorScreen != nil else {
            return
        }
        let trayPanel = ToastTrayPanel()
        trayPanel.setContent(ToastTrayView())
        panel = trayPanel
        repositionPanel()

        // Start scaled up + transparent, then shrink to natural size + fade in
        let finalFrame = trayPanel.frame
        let s = Self.scaleUp
        let expandedFrame = NSRect(
            x: finalFrame.midX - finalFrame.width * s / 2,
            y: finalFrame.midY - finalFrame.height * s / 2,
            width: finalFrame.width * s,
            height: finalFrame.height * s
        )
        trayPanel.setFrame(expandedFrame, display: false)
        trayPanel.alphaValue = 0
        trayPanel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            trayPanel.animator().setFrame(finalFrame, display: true)
            trayPanel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard let panel else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }

    private func repositionPanel() {
        guard let panel, let barWindow = anchorWindow, let screen = anchorScreen else {
            return
        }
        panel.reposition(anchoredBelow: barWindow.frame, on: screen)
    }
}
