import AppKit

/// Provides actual macOS app icons by dynamically searching running apps and installed applications.
/// No hardcoded mapping required — works on any Mac.
@MainActor
public final class AppIconProvider {
    public static let shared = AppIconProvider()

    /// Stores both positive and negative results to avoid repeated lookups.
    private var cache: [String: NSImage?] = [:]

    /// Maps lowercased app name → app bundle path. `nil` means scan hasn't completed yet.
    private var appPathIndex: [String: String]?

    private init() {
        // Build the installed-app index off the main thread at startup
        Task.detached(priority: .utility) {
            let index = AppIconProvider.scanInstalledApps()
            await MainActor.run {
                AppIconProvider.shared.appPathIndex = index
                // Clear negative cache entries so missed icons can be retried with the index
                AppIconProvider.shared.cache = AppIconProvider.shared.cache.filter { $0.value != nil }
            }
        }
    }

    /// Get the app icon for a given app name. Returns nil if not found.
    public func icon(for appName: String) -> NSImage? {
        if let cached = cache[appName] {
            return cached
        }

        let image = lookupIcon(for: appName)
        cache[appName] = image
        return image
    }

    /// Invalidate cache for a specific app (e.g., on launch/terminate).
    public func invalidate(appName: String) {
        cache.removeValue(forKey: appName)
    }

    private func lookupIcon(for appName: String) -> NSImage? {
        let lowerName = appName.lowercased()

        // 1. Search running applications (single case-insensitive pass)
        let runningApps = NSWorkspace.shared.runningApplications
        var caseInsensitiveMatch: NSRunningApplication?

        for app in runningApps {
            guard let name = app.localizedName else { continue }
            if name == appName {
                if let icon = app.icon { return icon }
                break
            }
            if caseInsensitiveMatch == nil, name.lowercased() == lowerName {
                caseInsensitiveMatch = app
            }
        }

        if let icon = caseInsensitiveMatch?.icon {
            return icon
        }

        // 2. Try well-known paths directly (fast path, no directory scan)
        let directPaths = [
            "/Applications/\(appName).app",
            "/Applications/Utilities/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app",
        ]

        for path in directPaths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }

        // 3. Fall back to installed app index (available once background scan completes)
        if let path = appPathIndex?[lowerName] {
            return NSWorkspace.shared.icon(forFile: path)
        }

        return nil
    }

    /// Scans /Applications directories and reads Info.plist to build name → path index.
    /// Designed to run off the main thread via Task.detached.
    private nonisolated static func scanInstalledApps() -> [String: String] {
        var index: [String: String] = [:]

        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "\(NSHomeDirectory())/Applications",
        ]

        let fm = FileManager.default
        for dir in searchDirs {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "app" else { continue }
                // Don't recurse into .app bundles
                enumerator.skipDescendants()

                let path = url.path
                let fileName = url.deletingPathExtension().lastPathComponent.lowercased()
                index[fileName] = path

                // Also index by CFBundleName / CFBundleDisplayName for apps whose
                // display name differs from filename (e.g. "Visual Studio Code.app" → "Code")
                let plistURL = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(
                          from: data, format: nil
                      ) as? [String: Any]
                else { continue }

                if let displayName = plist["CFBundleDisplayName"] as? String {
                    index[displayName.lowercased()] = path
                }
                if let bundleName = plist["CFBundleName"] as? String {
                    index[bundleName.lowercased()] = path
                }
            }
        }

        return index
    }
}
