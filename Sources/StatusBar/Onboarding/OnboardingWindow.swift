import AppKit
import SwiftUI

// MARK: - OnboardingKeys

enum OnboardingKeys {
    static let hasCompleted = "hasCompletedOnboarding"
}

// MARK: - OnboardingWindow

@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView {
            self.window?.close()
        }
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to StatusBar"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    // MARK: - NSWindowDelegate

    /// X ボタンでの閉じる操作でも "Get Started" 経由と同様に完了フラグを立てる。
    /// set(true) は冪等なので Get Started → close の順でも副作用はない。
    nonisolated func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: OnboardingKeys.hasCompleted)
    }
}
