import Foundation
import IOKit.ps

@MainActor
final class BatteryService {
    static let shared = BatteryService()

    private var runLoopSource: CFRunLoopSource?
    private var observers: [(Int, Bool, Bool) -> Void] = []
    private var started = false

    /// Whether the machine has a battery. False on desktop Macs (Mac Mini, Mac Pro, etc.).
    private(set) var hasBattery = true

    private init() {}

    func addObserver(_ handler: @escaping (_ capacity: Int, _ isCharging: Bool, _ hasBattery: Bool) -> Void) {
        observers.append(handler)
    }

    func removeAllObservers() {
        observers.removeAll()
    }

    func start() {
        guard !started else {
            // Already running - just poll once for the new observer
            poll()
            return
        }
        started = true
        poll()

        // IOPSNotificationCreateRunLoopSource for real-time updates.
        // Use Unmanaged.passUnretained since `shared` singleton is never deallocated.
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else {
                return
            }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            // Safely dispatch to MainActor instead of assumeIsolated,
            // since IOKit does not guarantee callback thread.
            Task { @MainActor in
                service.poll()
            }
        }, pointer).takeRetainedValue()

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    func stop() {
        guard started else {
            return
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        started = false
    }

    func poll() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        guard let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any]
        else {
            hasBattery = false
            notifyObservers(0, false, false)
            return
        }

        hasBattery = true
        let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        notifyObservers(capacity, isCharging, true)
    }

    private func notifyObservers(_ capacity: Int, _ isCharging: Bool, _ hasBattery: Bool) {
        for observer in observers {
            observer(capacity, isCharging, hasBattery)
        }
    }
}
