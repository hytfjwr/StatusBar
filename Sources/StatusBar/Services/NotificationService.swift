import Combine
import Foundation
import StatusBarKit

// MARK: - SustainedAlertState

/// Tracks whether a metric has exceeded a threshold for a sustained duration,
/// with a cooldown period to prevent rapid re-fires.
@MainActor
private struct SustainedAlertState {
    var exceedStart: Date?
    var notified = false
    var cooldownEnd: Date?

    mutating func reset() {
        exceedStart = nil
        notified = false
        cooldownEnd = nil
    }

    /// Returns `true` when alert should fire (first time crossing the sustained threshold).
    mutating func check(
        usage: Double,
        threshold: Double,
        sustainedDuration: Double,
        cooldown: TimeInterval
    ) -> Bool {
        let now = Date()
        if usage >= threshold {
            if exceedStart == nil {
                exceedStart = now
            }
            if let start = exceedStart,
               now.timeIntervalSince(start) >= sustainedDuration,
               !notified
            {
                notified = true
                cooldownEnd = now.addingTimeInterval(cooldown)
                return true
            }
        } else {
            exceedStart = nil
            if cooldownEnd.map({ now >= $0 }) ?? true {
                notified = false
                cooldownEnd = nil
            }
        }
        return false
    }
}

// MARK: - NotificationService

@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    private var timer: AnyCancellable?
    private var batteryObserverToken: BatteryService.ObserverToken?
    private let monitorService = SystemMonitorService.shared

    // Battery state
    private var currentBatteryPct: Int = 100
    private var currentBatteryCharging = false
    private var lastBatteryNotifPct: Int = 101 // sentinel: haven't notified yet

    private var cpuAlert = SustainedAlertState()
    private var memAlert = SustainedAlertState()

    private static let notificationCooldown: TimeInterval = 60

    private init() {}

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
            cpuAlert.reset()
            memAlert.reset()
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
            ToastManager.shared.post(ToastRequest(
                title: "Low Battery",
                message: "Battery is at \(currentBatteryPct)%",
                level: .warning
            ))
            EventBus.shared.emit(.batteryLow(percent: currentBatteryPct, threshold: threshold))
        }
    }

    // MARK: - CPU

    private func checkCPU(_ prefs: PreferencesModel) {
        guard prefs.notifyCPUHigh else {
            cpuAlert.reset()
            return
        }

        let usage = monitorService.cpuUsage() * 100
        let threshold = prefs.cpuThreshold

        if cpuAlert.check(
            usage: usage,
            threshold: threshold,
            sustainedDuration: prefs.cpuSustainedDuration,
            cooldown: Self.notificationCooldown
        ) {
            ToastManager.shared.post(ToastRequest(
                title: "High CPU Usage",
                message: String(format: "CPU has been above %.0f%% for %.0fs", threshold, prefs.cpuSustainedDuration),
                level: .warning,
                actionLabel: "Activity Monitor",
                actionShellCommand: "open -a 'Activity Monitor'"
            ))
            EventBus.shared.emit(.cpuHigh(
                usagePercent: Int(usage),
                threshold: Int(threshold),
                sustainedSeconds: Int(prefs.cpuSustainedDuration)
            ))
        }
    }

    // MARK: - Memory

    private func checkMemory(_ prefs: PreferencesModel) {
        guard prefs.notifyMemoryHigh else {
            memAlert.reset()
            return
        }

        let usage = monitorService.memoryUsage() * 100
        let threshold = prefs.memoryThreshold

        if memAlert.check(
            usage: usage,
            threshold: threshold,
            sustainedDuration: prefs.memorySustainedDuration,
            cooldown: Self.notificationCooldown
        ) {
            ToastManager.shared.post(ToastRequest(
                title: "High Memory Usage",
                message: String(format: "Memory has been above %.0f%% for %.0fs", threshold, prefs.memorySustainedDuration),
                level: .warning,
                actionLabel: "Activity Monitor",
                actionShellCommand: "open -a 'Activity Monitor'"
            ))
            EventBus.shared.emit(.memoryHigh(
                usagePercent: Int(usage),
                threshold: Int(threshold),
                sustainedSeconds: Int(prefs.memorySustainedDuration)
            ))
        }
    }
}
