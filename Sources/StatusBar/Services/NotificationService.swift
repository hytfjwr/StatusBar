import Combine
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.statusbar", category: "NotificationService")

// MARK: - NotificationService

@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    private(set) var isAvailable: Bool = false
    private(set) var permissionStatus: String = "Unknown"

    private var timer: AnyCancellable?
    private var batteryObserverToken: BatteryService.ObserverToken?
    private let monitorService = SystemMonitorService.shared

    // Battery state
    private var currentBatteryPct: Int = 100
    private var currentBatteryCharging = false
    private var lastBatteryNotifPct: Int = 101 // sentinel: haven't notified yet

    // CPU sustained state
    private var cpuExceedStart: Date?
    private var cpuNotified = false
    private var cpuCooldownEnd: Date?

    // Memory sustained state
    private var memExceedStart: Date?
    private var memNotified = false
    private var memCooldownEnd: Date?

    private static let notificationCooldown: TimeInterval = 60

    private init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
    }

    func start() {
        stop()

        batteryObserverToken = BatteryService.shared.addObserver { [weak self] pct, charging, _ in
            self?.currentBatteryPct = pct
            self?.currentBatteryCharging = charging
        }
        BatteryService.shared.start()

        updateTimerState()
        observeNotificationPrefs()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let token = batteryObserverToken {
            BatteryService.shared.removeObserver(token)
            batteryObserverToken = nil
        }
    }

    private func updateTimerState() {
        let prefs = PreferencesModel.shared
        let anyEnabled = prefs.notifyBatteryLow || prefs.notifyCPUHigh || prefs.notifyMemoryHigh

        if anyEnabled, timer == nil {
            timer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.check() }
        } else if !anyEnabled {
            timer?.cancel()
            timer = nil
            // Reset sustained state
            cpuExceedStart = nil
            cpuNotified = false
            cpuCooldownEnd = nil
            memExceedStart = nil
            memNotified = false
            memCooldownEnd = nil
        }
    }

    private func observeNotificationPrefs() {
        withObservationTracking {
            let prefs = PreferencesModel.shared
            _ = prefs.notifyBatteryLow
            _ = prefs.notifyCPUHigh
            _ = prefs.notifyMemoryHigh
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateTimerState()
                self?.observeNotificationPrefs()
            }
        }
    }

    func requestPermission() {
        guard isAvailable else {
            logger.warning("Notifications unavailable: no bundle identifier (SPM debug build)")
            permissionStatus = "Unavailable (no bundle ID)"
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor [weak self] in
                if let error {
                    logger.warning("Notification permission error: \(error.localizedDescription)")
                    self?.permissionStatus = "Error"
                } else {
                    self?.permissionStatus = granted ? "Granted" : "Denied"
                    logger.info("Notification permission \(granted ? "granted" : "denied")")
                }
            }
        }
    }

    func refreshPermissionStatus() {
        guard isAvailable else {
            permissionStatus = "Unavailable (no bundle ID)"
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in
                switch status {
                case .authorized: self?.permissionStatus = "Granted"
                case .denied: self?.permissionStatus = "Denied"
                case .notDetermined: self?.permissionStatus = "Not Requested"
                case .provisional: self?.permissionStatus = "Provisional"
                default: self?.permissionStatus = "Unknown"
                }
            }
        }
    }

    // MARK: - Check Loop

    private func check() {
        let prefs = PreferencesModel.shared
        checkBattery(prefs)
        checkCPU(prefs)
        checkMemory(prefs)
    }

    // MARK: - Battery

    private func checkBattery(_ prefs: PreferencesModel) {
        guard prefs.notifyBatteryLow else {
            return
        }

        // Reset notification state when charging
        if currentBatteryCharging {
            lastBatteryNotifPct = 101
            return
        }

        let threshold = Int(prefs.batteryThreshold)

        // Fire once when dropping below threshold (not every tick)
        if currentBatteryPct <= threshold, currentBatteryPct < lastBatteryNotifPct {
            lastBatteryNotifPct = currentBatteryPct
            postNotification(
                id: "battery-low",
                title: "Low Battery",
                body: "Battery is at \(currentBatteryPct)%"
            )
        }
    }

    // MARK: - CPU

    private func checkCPU(_ prefs: PreferencesModel) {
        guard prefs.notifyCPUHigh else {
            cpuExceedStart = nil
            cpuNotified = false
            return
        }

        let usage = monitorService.cpuUsage() * 100 // 0...100
        let threshold = prefs.cpuThreshold

        if usage >= threshold {
            if cpuExceedStart == nil {
                cpuExceedStart = Date()
            }
            if let start = cpuExceedStart,
               Date().timeIntervalSince(start) >= prefs.cpuSustainedDuration,
               !cpuNotified
            {
                cpuNotified = true
                cpuCooldownEnd = Date().addingTimeInterval(Self.notificationCooldown)
                postNotification(
                    id: "cpu-high",
                    title: "High CPU Usage",
                    body: String(format: "CPU has been above %.0f%% for %.0fs", threshold, prefs.cpuSustainedDuration)
                )
            }
        } else {
            cpuExceedStart = nil
            // Only reset notified state after cooldown to prevent rapid re-fires
            if let cooldown = cpuCooldownEnd, Date() < cooldown {
                // still in cooldown
            } else {
                cpuNotified = false
                cpuCooldownEnd = nil
            }
        }
    }

    // MARK: - Memory

    private func checkMemory(_ prefs: PreferencesModel) {
        guard prefs.notifyMemoryHigh else {
            memExceedStart = nil
            memNotified = false
            return
        }

        let usage = monitorService.memoryUsage() * 100 // 0...100
        let threshold = prefs.memoryThreshold

        if usage >= threshold {
            if memExceedStart == nil {
                memExceedStart = Date()
            }
            if let start = memExceedStart,
               Date().timeIntervalSince(start) >= prefs.memorySustainedDuration,
               !memNotified
            {
                memNotified = true
                memCooldownEnd = Date().addingTimeInterval(Self.notificationCooldown)
                postNotification(
                    id: "memory-high",
                    title: "High Memory Usage",
                    body: String(format: "Memory has been above %.0f%% for %.0fs", threshold, prefs.memorySustainedDuration)
                )
            }
        } else {
            memExceedStart = nil
            if let cooldown = memCooldownEnd, Date() < cooldown {
                // still in cooldown
            } else {
                memNotified = false
                memCooldownEnd = nil
            }
        }
    }

    // MARK: - Post

    private func postNotification(id: String, title: String, body: String) {
        guard isAvailable else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.statusbar.\(id)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}
