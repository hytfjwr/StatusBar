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

    private func showPanel() {
        guard panel == nil, anchorScreen != nil else {
            return
        }
        let trayPanel = ToastTrayPanel()
        trayPanel.setContent(ToastTrayView())
        panel = trayPanel
        repositionPanel()

        trayPanel.orderFront(nil)
    }

    private func hidePanel() {
        guard let panel else {
            return
        }
        // アニメ完了まで self.panel を保持したままだと、その 0.25s 窓内で post() された際に
        // showPanel() の `guard panel == nil` によって新規パネルが生成されず表示されない。
        // 退避してから直ちに nil にすることで、後続の post() が新しいパネルを生成できるようにする。
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func repositionPanel() {
        guard let panel, let barWindow = anchorWindow, let screen = anchorScreen else {
            return
        }
        panel.reposition(anchoredBelow: barWindow.frame, on: screen)
    }
}
