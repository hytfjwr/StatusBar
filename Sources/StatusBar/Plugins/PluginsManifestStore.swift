import Foundation
import OSLog
import Yams

private let logger = Logger(subsystem: "com.statusbar", category: "PluginsManifestStore")

// MARK: - PluginsManifest

/// Top-level structure of plugins.yml. Declarative — the user's intent.
struct PluginsManifest: Codable, Equatable {
    var plugins: [PluginsManifestEntry]

    init(plugins: [PluginsManifestEntry] = []) {
        self.plugins = plugins
    }

    static let empty = Self()
}

// MARK: - PluginsManifestEntry

/// One entry in plugins.yml.
struct PluginsManifestEntry: Codable, Equatable {
    /// `github:owner/repo` format.
    var source: String
    /// `"1.2.0"` (exact) or `"latest"`.
    var version: String

    /// True when both halves of `owner/repo` start alphanumeric and only use `[A-Za-z0-9._-]` —
    /// matches `GitHubPluginInstaller.parseGitHubURL` and rejects `.`/`..` (path traversal).
    private static func validateOwnerRepo(owner: Substring, repo: Substring) -> Bool {
        let pattern = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/
        return owner.wholeMatch(of: pattern) != nil && repo.wholeMatch(of: pattern) != nil
    }

    /// Parse `github:owner/repo` into the (owner, repo) tuple. Returns nil for malformed entries.
    func parseGitHubSource() -> (owner: String, repo: String)? {
        guard source.hasPrefix("github:") else {
            return nil
        }
        let path = source.dropFirst("github:".count)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, Self.validateOwnerRepo(owner: parts[0], repo: parts[1]) else {
            return nil
        }
        return (String(parts[0]), String(parts[1]))
    }

    /// Convert a "https://github.com/owner/repo" URL into the `github:owner/repo` form used by plugins.yml.
    /// Inverse of `parseGitHubSource()`.
    static func source(fromGitHubURL url: String?) -> String? {
        guard let url else {
            return nil
        }
        let prefix = "https://github.com/"
        guard url.hasPrefix(prefix) else {
            return nil
        }
        let path = url.dropFirst(prefix.count)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, validateOwnerRepo(owner: parts[0], repo: parts[1]) else {
            return nil
        }
        return "github:\(parts[0])/\(parts[1])"
    }

    var isLatest: Bool {
        version == "latest"
    }
}

// MARK: - PluginsLock

/// Top-level structure of plugins-lock.yml. Resolved facts — re-installable snapshot.
struct PluginsLock: Codable, Equatable {
    /// Schema version for forward compatibility.
    var lockfileVersion: Int
    var plugins: [PluginsLockEntry]

    init(lockfileVersion: Int = 1, plugins: [PluginsLockEntry] = []) {
        self.lockfileVersion = lockfileVersion
        self.plugins = plugins
    }

    static let empty = Self()
}

// MARK: - PluginsLockEntry

/// One resolved entry in plugins-lock.yml.
struct PluginsLockEntry: Codable, Equatable {
    /// Matches the `source` in plugins.yml ("github:owner/repo").
    var source: String
    /// Concrete version that was resolved (no leading "v").
    var resolvedVersion: String
    /// Matching `DylibPluginManifest.id` (e.g. "com.example.weather").
    var pluginID: String
    /// Bundle directory name without the `.statusplugin` extension.
    var bundleName: String
    /// Download URL of the `.statusplugin.zip` asset (nil only after a migration before the first sync).
    var assetURL: String?
    /// SHA-256 of the downloaded zip (hex, lowercase). Nil only after migration.
    var zipSHA256: String?
    /// When this lock entry was resolved.
    var resolvedAt: Date
}

// MARK: - PluginsManifestStore

/// Persists plugins.yml and plugins-lock.yml under `~/.config/statusbar/` and watches
/// the manifest for external edits. Sync logic lives in `PluginsManager` — this type
/// is purely I/O + change notification.
@MainActor
@Observable
final class PluginsManifestStore {
    static let shared = PluginsManifestStore()

    /// Last successfully loaded manifest. Defaults to empty when no file exists.
    private(set) var currentManifest: PluginsManifest = .empty
    /// Last successfully loaded lock. Defaults to empty when no file exists.
    private(set) var currentLock: PluginsLock = .empty

    let manifestURL: URL
    let lockURL: URL

    /// Manifest size cap — large enough for hundreds of entries, small enough to reject billion-laughs attacks.
    private static let maxManifestFileSize: UInt64 = 262_144 // 256 KB

    private var fsSource: DispatchSourceFileSystemObject?
    private var fsDebounceTask: Task<Void, Never>?
    private var lastKnownManifestModDate: Date?

    private var lastWriteTime: Date?
    private let writeGracePeriod: TimeInterval = 0.5

    /// On-edit callback used by `PluginsManager` to surface a toast.
    var onExternalEdit: (@MainActor () -> Void)?

    private init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar", isDirectory: true)
        manifestURL = configDir.appendingPathComponent("plugins.yml")
        lockURL = configDir.appendingPathComponent("plugins-lock.yml")
    }

    /// Testable initializer accepting custom file URLs.
    init(manifestURL: URL, lockURL: URL) {
        self.manifestURL = manifestURL
        self.lockURL = lockURL
    }

    // MARK: - Existence

    var manifestExists: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    var lockExists: Bool {
        FileManager.default.fileExists(atPath: lockURL.path)
    }

    // MARK: - Load

    /// Initial load called once from bootstrap. Missing or unparseable files yield empty defaults so
    /// the app can keep running; a malformed plugins.yml at startup is treated as no manifest at all
    /// (the user can fix the file and trigger a sync).
    func load() {
        do {
            currentManifest = try loadManifestFromDisk()
        } catch {
            logger.error("Failed to load plugins.yml — using empty manifest: \(error.localizedDescription)")
            currentManifest = .empty
        }
        do {
            currentLock = try loadLockFromDisk()
        } catch {
            logger.error("Failed to load plugins-lock.yml — using empty lock: \(error.localizedDescription)")
            currentLock = .empty
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
           let modDate = attrs[.modificationDate] as? Date
        {
            lastKnownManifestModDate = modDate
        }
    }

    /// Re-read plugins.yml after an external edit. Throws on parse error so the caller can preserve
    /// the previously valid in-memory manifest rather than silently degrading to empty (which would
    /// cause `sync()` to drift-uninstall every managed plugin).
    func reload() throws {
        currentManifest = try loadManifestFromDisk()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
           let modDate = attrs[.modificationDate] as? Date
        {
            lastKnownManifestModDate = modDate
        }
    }

    private func loadManifestFromDisk() throws -> PluginsManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .empty
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        let size = attrs[.size] as? UInt64 ?? 0
        guard size <= Self.maxManifestFileSize else {
            throw PluginsManifestError.fileTooLarge
        }
        let data = try Data(contentsOf: manifestURL)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        return try YAMLDecoder().decode(PluginsManifest.self, from: yaml)
    }

    private func loadLockFromDisk() throws -> PluginsLock {
        guard FileManager.default.fileExists(atPath: lockURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: lockURL)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        return try YAMLDecoder().decode(PluginsLock.self, from: yaml)
    }

    // MARK: - Save

    /// Persist a manifest and update `currentManifest` on success.
    func saveManifest(_ manifest: PluginsManifest) throws {
        try ensureParentDirectoryExists(for: manifestURL)
        lastWriteTime = Date()
        let yaml = try YAMLEncoder().encode(manifest)
        try Data(yaml.utf8).write(to: manifestURL, options: .atomic)
        currentManifest = manifest
        if let attrs = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
           let modDate = attrs[.modificationDate] as? Date
        {
            lastKnownManifestModDate = modDate
        }
    }

    /// Persist a lock file and update `currentLock` on success.
    func saveLock(_ lock: PluginsLock) throws {
        try ensureParentDirectoryExists(for: lockURL)
        lastWriteTime = Date()
        let yaml = try YAMLEncoder().encode(lock)
        try Data(yaml.utf8).write(to: lockURL, options: .atomic)
        currentLock = lock
    }

    private func ensureParentDirectoryExists(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
    }

    // MARK: - File watching

    /// Start watching the config directory for external edits to plugins.yml.
    func startWatching() {
        guard fsSource == nil else {
            return
        }
        let dirPath = manifestURL.deletingLastPathComponent().path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("Failed to open plugins config directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleManifestCheck()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fsSource = source
    }

    func stopWatching() {
        fsSource?.cancel()
        fsSource = nil
        fsDebounceTask?.cancel()
        fsDebounceTask = nil
    }

    private func scheduleManifestCheck() {
        fsDebounceTask?.cancel()
        fsDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                return
            }
            self?.checkManifestChanged()
        }
    }

    private func checkManifestChanged() {
        // Ignore events shortly after our own writes (the grace window prevents echoes).
        if let lastWrite = lastWriteTime, Date().timeIntervalSince(lastWrite) < writeGracePeriod {
            return
        }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: manifestURL.path),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return
        }
        if let lastMod = lastKnownManifestModDate, modDate <= lastMod {
            return
        }
        lastKnownManifestModDate = modDate
        onExternalEdit?()
    }
}

// MARK: - PluginsManifestError

enum PluginsManifestError: Error, LocalizedError {
    case fileTooLarge
    case invalidSource(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "plugins.yml exceeds the 256 KB size limit"
        case let .invalidSource(source):
            "Invalid source (expected github:owner/repo): \(source)"
        }
    }
}
