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

    /// Mark onboarding complete when closed via the X button, just as "Get Started" does.
    /// set(true) is idempotent, so the Get Started → close sequence has no side effects.
    nonisolated func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: OnboardingKeys.hasCompleted)
    }
}
