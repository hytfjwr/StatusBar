import AppKit

// Single-instance guard: exit if another StatusBar is already running
let myPID = ProcessInfo.processInfo.processIdentifier
let isDuplicate: Bool = {
    // Check by bundle identifier (installed .app)
    if let bid = Bundle.main.bundleIdentifier {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        if others.contains(where: { $0.processIdentifier != myPID && !$0.isTerminated }) {
            return true
        }
    }
    // Check by executable name (development builds without bundle ID)
    let myName = ProcessInfo.processInfo.processName
    return NSWorkspace.shared.runningApplications.contains {
        $0.processIdentifier != myPID
            && !$0.isTerminated
            && $0.executableURL?.lastPathComponent == myName
    }
}()

if isDuplicate {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
