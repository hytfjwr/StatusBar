import Foundation
import IOKit.ps

@MainActor
final class BatteryService {
    private let onChange: @Sendable (Int, Bool) -> Void
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<BatteryService>?

    init(onChange: @escaping @Sendable (Int, Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard retainedSelf == nil else { return }
        poll()

        // IOPSNotificationCreateRunLoopSource for real-time updates
        // Use passRetained to prevent use-after-free if service is released before stop()
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else {
                return
            }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                service.poll()
            }
        }, retained.toOpaque()).takeRetainedValue()

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
    }

    func poll() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        guard let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any]
        else {
            onChange(0, false)
            return
        }

        let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        onChange(capacity, isCharging)
    }
}
