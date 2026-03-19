import AppKit

/// Checks which screens currently have a native fullscreen window.
/// Fetches the window list once and checks all screens in a single pass.
enum FullscreenDetector {
    static func fullscreenScreenIndices(for screens: [NSScreen]) -> Set<Int> {
        guard !screens.isEmpty,
              let windowInfoList = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]]
        else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let mainScreenHeight = screens.first?.frame.height ?? 0

        // Pre-compute CG-coordinate Y origins for each screen
        let screenCGYs = screens.map { mainScreenHeight - $0.frame.maxY }

        var result = Set<Int>()

        for info in windowInfoList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else {
                continue
            }

            var windowRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &windowRect)
            else {
                continue
            }

            for (index, screen) in screens.enumerated() where !result.contains(index) {
                if abs(windowRect.width - screen.frame.width) < 2,
                   abs(windowRect.height - screen.frame.height) < 2,
                   abs(windowRect.origin.x - screen.frame.origin.x) < 2,
                   abs(windowRect.origin.y - screenCGYs[index]) < 2
                {
                    result.insert(index)
                }
            }

            // Early exit if all screens matched
            if result.count == screens.count {
                break
            }
        }
        return result
    }
}
