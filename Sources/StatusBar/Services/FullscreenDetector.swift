import AppKit

// MARK: - Private CGS API

private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

// MARK: - FullscreenDetector

/// Detects which screens currently have a native fullscreen app.
/// Uses private CGS API to avoid Screen Recording permission which disables HDCP.
enum FullscreenDetector {
    private static let fullscreenSpaceType = 4

    static func fullscreenScreenIndices(for screens: [NSScreen]) -> Set<Int> {
        guard !screens.isEmpty,
              let displaySpaces = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]]
        else {
            return []
        }

        var uuidToIndex: [String: Int] = [:]
        for (index, screen) in screens.enumerated() {
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
            else {
                continue
            }
            if let cfUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber) {
                let uuid = cfUUID.takeRetainedValue()
                uuidToIndex[CFUUIDCreateString(nil, uuid) as String] = index
            }
        }

        var result = Set<Int>()

        for display in displaySpaces {
            guard let currentSpace = display["Current Space"] as? [String: Any],
                  let spaceType = currentSpace["type"] as? Int,
                  spaceType == fullscreenSpaceType,
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }

            // Display identifier format varies across macOS versions; contains() handles both
            // bare UUID strings and URN-wrapped forms.
            if let (_, index) = uuidToIndex.first(where: { displayID.contains($0.key) }) {
                result.insert(index)
            }
        }

        return result
    }
}
