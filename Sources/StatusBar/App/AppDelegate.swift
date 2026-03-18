import AppKit
import ApplicationServices
import StatusBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        checkAccessibilityPermission()

        // Load YAML config before anything else accesses PreferencesModel
        ConfigLoader.shared.bootstrap()

        Theme.configure(provider: PreferencesModel.shared)

        let registry = WidgetRegistry.shared
        registry.onLayoutDidChange = {
            PreferencesModel.shared.bump()
            ConfigLoader.shared.scheduleWrite()
        }

        // Built-in widgets
        registry.register(AppleMenuWidget())
        registry.register(ChevronWidget())
        registry.register(FrontAppWidget())
        registry.register(FocusTimerWidget())
        registry.register(MicCameraWidget())
        registry.register(NetworkWidget())
        registry.register(MemoryGraphWidget())
        registry.register(CPUGraphWidget())
        registry.register(DiskUsageWidget())
        registry.register(BatteryWidget())
        registry.register(VolumeWidget())
        registry.register(InputSourceWidget())
        registry.register(DateWidget())
        registry.register(TimeWidget())
        registry.register(BluetoothWidget())

        // Dylib plugins (user-installed from ~/.config/statusbar/plugins/)
        DylibPluginLoader.shared.loadAll(into: registry)

        registry.finalizeRegistration()

        // Apply layout from config after all widgets are registered
        ConfigLoader.shared.applyLayoutIfNeeded()

        controller = StatusBarController()
        controller?.setup()

        NotificationService.shared.start()
    }

    /// Set up a minimal main menu so standard text editing shortcuts (Cmd+C/V/X/A) work.
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        editItem.submenu = {
            let menu = NSMenu(title: "Edit")
            menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            return menu
        }()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// Accessibility 権限を確認し、未付与の場合はシステムダイアログを表示する。
    /// グローバルイベントモニター（自動非表示、ポップアップ外部クリック閉じ）に必要。
    private func checkAccessibilityPermission() {
        // kAXTrustedCheckOptionPrompt の値は "AXTrustedCheckOptionPrompt"
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationService.shared.stop()
        controller?.teardown()
        ConfigLoader.shared.teardown()
    }
}
