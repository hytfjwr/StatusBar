import AppKit
import StatusBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    private var configErrorObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

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

        IPCServer.shared.start()

        // Show onboarding on first launch
        if ConfigLoader.shared.isFirstLaunch
            || !UserDefaults.standard.bool(forKey: OnboardingKeys.hasCompleted)
        {
            OnboardingWindow.shared.show()
        }

        // Background update check (throttled to once per hour)
        Task {
            await AppUpdateService.shared.checkIfNeeded()
        }

        configErrorObserver = NotificationCenter.default.addObserver(
            forName: .configParseError,
            object: nil,
            queue: .main
        ) { notification in
            let message = notification.userInfo?["message"] as? String
                ?? "Unknown error"
            Task { @MainActor in
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Config Reload Failed"
                alert.informativeText = "config.yml could not be parsed."
                    + " The previous working configuration will continue to be used.\n\n\(message)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
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

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = configErrorObserver {
            NotificationCenter.default.removeObserver(observer)
            configErrorObserver = nil
        }
        IPCServer.shared.stop()
        NotificationService.shared.stop()
        controller?.teardown()
        ConfigLoader.shared.teardown()
    }
}
