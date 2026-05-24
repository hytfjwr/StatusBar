import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "PluginsManager")

// MARK: - PluginsSyncResult

struct PluginsSyncResult {
    var installed: [String] = []
    var updated: [String] = []
    var uninstalled: [String] = []
    var skipped: [String] = []
    var errors: [(source: String, message: String)] = []

    var hasErrors: Bool {
        !errors.isEmpty
    }

    var changedSomething: Bool {
        !installed.isEmpty || !updated.isEmpty || !uninstalled.isEmpty
    }

    /// Short human-readable summary for toasts and UI labels.
    var summary: String {
        let parts: [String] = [
            installed.isEmpty ? nil : "\(installed.count) installed",
            updated.isEmpty ? nil : "\(updated.count) updated",
            uninstalled.isEmpty ? nil : "\(uninstalled.count) removed",
        ].compactMap(\.self)
        return parts.isEmpty ? "Already up to date" : parts.joined(separator: ", ")
    }
}

// MARK: - PluginsManager

/// Orchestrates plugins.yml + plugins-lock.yml + registry.json. Mirrors npm/pnpm semantics:
/// plugins.yml is the user intent, plugins-lock.yml is the resolved snapshot, registry.json
/// is the runtime state (enabled / installedAt / isLocal).
@MainActor
@Observable
final class PluginsManager {
    static let shared = PluginsManager()

    let manifestStore: PluginsManifestStore
    let pluginStore: PluginStore
    let installer: GitHubPluginInstaller

    /// True when plugins.yml has been edited externally since the last successful sync.
    private(set) var isDirty: Bool = false

    /// In-flight sync task — used to coalesce concurrent sync() callers.
    private var inFlightSync: Task<PluginsSyncResult, any Error>?

    /// Tail of the serialized mutation chain (add / remove). New mutators await this so
    /// concurrent CLI installs / uninstalls cannot interleave their manifest+lock writes.
    /// `Result<Void, Never>` so a failed predecessor never propagates and blocks the queue.
    private var mutationTail: Task<Void, Never>?

    private init() {
        manifestStore = .shared
        pluginStore = .shared
        installer = .shared
    }

    /// Testable initializer accepting DI for manifest store, plugin store, and installer.
    init(manifestStore: PluginsManifestStore, pluginStore: PluginStore, installer: GitHubPluginInstaller) {
        self.manifestStore = manifestStore
        self.pluginStore = pluginStore
        self.installer = installer
    }

    // MARK: - Bootstrap

    /// Called once from `AppDelegate` after `ConfigLoader.bootstrap()` and before
    /// `DylibPluginLoader.loadAll(into:)`. Loads files, performs first-run migration,
    /// and starts FS watching.
    func bootstrap() {
        manifestStore.load()
        do {
            if try migrateIfNeeded() {
                ToastManager.shared.post(ToastRequest(
                    title: "plugins.yml created",
                    message: "Generated from existing plugin registry. Run sync to record checksums.",
                    icon: "doc.text",
                    level: .info,
                    duration: 5
                ))
            }
        } catch {
            logger.error("Plugin manifest migration failed: \(error.localizedDescription)")
        }
        manifestStore.onExternalEdit = { [weak self] in
            self?.handleExternalEdit()
        }
        manifestStore.startWatching()
    }

    func teardown() {
        manifestStore.stopWatching()
    }

    // MARK: - Migration

    /// On first run with an existing `registry.json` and no `plugins.yml`, generate
    /// `plugins.yml` and `plugins-lock.yml` from the GitHub-installed plugins in the registry.
    /// Local (`isLocal == true`) plugins are intentionally excluded.
    /// - Returns: True when a new manifest+lock pair was written.
    @discardableResult
    func migrateIfNeeded() throws -> Bool {
        if manifestStore.manifestExists {
            return false
        }
        // PluginStore is loaded lazily by DylibPluginLoader; load it now so migration sees current state.
        do {
            try pluginStore.load()
        } catch {
            logger.warning("Could not load plugin registry for migration: \(error.localizedDescription)")
        }
        let githubPlugins = pluginStore.plugins.filter { !$0.isLocal && $0.githubURL != nil }
        guard !githubPlugins.isEmpty else {
            return false
        }

        var manifestEntries: [PluginsManifestEntry] = []
        var lockEntries: [PluginsLockEntry] = []
        for record in githubPlugins {
            guard let source = PluginsManifestEntry.source(fromGitHubURL: record.githubURL) else {
                continue
            }
            let normalizedVersion = GitHubPluginInstaller.normalizeVersion(record.version)
            manifestEntries.append(PluginsManifestEntry(source: source, version: normalizedVersion))
            // assetURL/zipSHA256 are unknown at migration time — the next non-frozen sync fills them in.
            lockEntries.append(PluginsLockEntry(
                source: source,
                resolvedVersion: normalizedVersion,
                pluginID: record.id,
                bundleName: record.bundleName,
                assetURL: nil,
                zipSHA256: nil,
                resolvedAt: record.installedAt
            ))
        }

        try manifestStore.saveManifest(PluginsManifest(plugins: manifestEntries))
        try manifestStore.saveLock(PluginsLock(plugins: lockEntries))
        logger.info("Migrated \(githubPlugins.count) plugin(s) to plugins.yml + plugins-lock.yml")
        return true
    }

    // MARK: - Sync

    /// Reconcile installed plugins with `plugins.yml`. Installs missing plugins, updates
    /// outdated ones, removes plugins that are no longer declared, and refreshes the lockfile.
    /// Concurrent callers share a single in-flight sync to avoid duplicate downloads.
    /// - Parameter frozen: When true, resolves only from `plugins-lock.yml` and never contacts GitHub.
    func sync(frozen: Bool = false) async throws -> PluginsSyncResult {
        // Coalesce concurrent sync callers (they want the same result, no point doing the work
        // twice). Also queue behind any in-flight add/remove via the shared mutation chain so
        // a sync mid-install doesn't clobber the lockfile from a stale snapshot.
        if let existing = inFlightSync {
            return try await existing.value
        }
        let task = Task<PluginsSyncResult, any Error> { @MainActor [weak self] () throws -> PluginsSyncResult in
            guard let self else {
                return PluginsSyncResult()
            }
            defer { self.inFlightSync = nil }
            return try await self.serializeMutation { [self] in
                try await runSync(frozen: frozen)
            }
        }
        inFlightSync = task
        return try await task.value
    }

    private func runSync(frozen: Bool) async throws -> PluginsSyncResult {
        let manifest = manifestStore.currentManifest
        let lock = manifestStore.currentLock

        var result = PluginsSyncResult()
        var newLockEntries: [PluginsLockEntry] = []

        for entry in manifest.plugins {
            do {
                let outcome = try await applyEntry(entry, lock: lock, frozen: frozen)
                newLockEntries.append(outcome.lockEntry)
                switch outcome.action {
                case .skipped:
                    result.skipped.append(outcome.lockEntry.pluginID)
                case .installed:
                    result.installed.append(outcome.lockEntry.pluginID)
                case .updated:
                    result.updated.append(outcome.lockEntry.pluginID)
                }
            } catch {
                logger.error("Sync failed for \(entry.source): \(error.localizedDescription)")
                result.errors.append((source: entry.source, message: error.localizedDescription))
                // Preserve the previous lock entry if any, so partial failures don't lose state.
                if let existing = lock.plugins.first(where: { $0.source == entry.source }) {
                    newLockEntries.append(existing)
                }
            }
        }

        // Drift: registry has non-local plugins that are not declared in plugins.yml → uninstall.
        // GitHub repository names are case-insensitive, so normalize for comparison.
        let declaredSources = Set(manifest.plugins.map { $0.source.lowercased() })
        for record in pluginStore.plugins where !record.isLocal {
            guard let source = PluginsManifestEntry.source(fromGitHubURL: record.githubURL),
                  !declaredSources.contains(source.lowercased())
            else {
                continue
            }
            do {
                try installer.uninstall(pluginID: record.id)
                DylibPluginLoader.shared.markForRemoval(pluginID: record.id, from: WidgetRegistry.shared)
                result.uninstalled.append(record.id)
            } catch {
                logger.error("Failed to uninstall drift plugin \(record.id): \(error.localizedDescription)")
                result.errors.append((source: source, message: error.localizedDescription))
            }
        }

        try manifestStore.saveLock(PluginsLock(plugins: newLockEntries))
        isDirty = false
        return result
    }

    // MARK: - GUI helpers

    /// Outcome of `add(source:version:)`. `action` lets callers skip a hot-reload when nothing
    /// on disk changed — without it, repeating `sbar plugins install foo` would tear down + rebuild
    /// the live widgets at the same version, losing per-widget runtime state.
    struct AddResult {
        enum Action { case installed, updated, skipped }
        let record: InstalledPluginRecord
        let action: Action
    }

    /// Append (or update) an entry in plugins.yml and immediately install the plugin.
    /// Installs first and only persists the manifest if the install succeeds, so a failed
    /// network request never leaves a poisoned entry in plugins.yml.
    @discardableResult
    func add(source: String, version: String) async throws -> AddResult {
        try await serializeMutation { [self] in
            try await unsafeAdd(source: source, version: version)
        }
    }

    private func unsafeAdd(source: String, version: String) async throws -> AddResult {
        let entry = PluginsManifestEntry(source: source, version: version)
        guard entry.parseGitHubSource() != nil else {
            throw PluginsManifestError.invalidSource(source)
        }

        // Install first so a failure does not pollute plugins.yml.
        let outcome = try await applyEntry(entry, lock: manifestStore.currentLock, frozen: false)

        // GitHub repo names are case-insensitive — match the existing manifest/lock entry
        // case-insensitively so re-installing with a different casing updates rather than
        // duplicating, matching the drift-comparison convention used in runSync().
        let target = source.lowercased()

        // Persist manifest (update existing entry if present, otherwise append).
        var manifest = manifestStore.currentManifest
        if let index = manifest.plugins.firstIndex(where: { $0.source.lowercased() == target }) {
            manifest.plugins[index] = entry
        } else {
            manifest.plugins.append(entry)
        }
        try manifestStore.saveManifest(manifest)

        // Persist lock.
        var updatedLock = manifestStore.currentLock
        if let index = updatedLock.plugins.firstIndex(where: { $0.source.lowercased() == target }) {
            updatedLock.plugins[index] = outcome.lockEntry
        } else {
            updatedLock.plugins.append(outcome.lockEntry)
        }
        try manifestStore.saveLock(updatedLock)
        let action: AddResult.Action = switch outcome.action {
        case .installed: .installed
        case .updated: .updated
        case .skipped: .skipped
        }
        return AddResult(record: outcome.record, action: action)
    }

    /// Remove a plugin by its plugins.yml source ("github:owner/repo"). Resolves to a pluginID
    /// via the lockfile (preferred) or the installed registry, then delegates to `remove(pluginID:)`.
    /// Matching is case-insensitive because GitHub repository names are case-insensitive — this
    /// mirrors the drift-detection logic in `runSync()`.
    /// When neither pluginStore nor any other ground-truth source has a record but the lockfile
    /// does (e.g., the plugin failed to load at boot), the manifest+lock entries are removed
    /// directly so the user can recover via CLI without hand-editing plugins.yml.
    /// `async` so it can wait for an in-flight `add()` to finish before mutating the manifest.
    func remove(source: String) async throws {
        try await serializeMutation { [self] in
            try unsafeRemove(source: source)
        }
    }

    private func unsafeRemove(source: String) throws {
        let target = source.lowercased()
        if let record = pluginStore.plugins.first(where: {
            PluginsManifestEntry.source(fromGitHubURL: $0.githubURL)?.lowercased() == target
        }) {
            try unsafeRemove(pluginID: record.id)
            return
        }
        if manifestStore.currentLock.plugins.contains(where: { $0.source.lowercased() == target }) {
            // Orphan lock entry (no matching registry record). Clear manifest+lock without
            // calling installer.uninstall — there's nothing on disk to remove.
            var manifest = manifestStore.currentManifest
            manifest.plugins.removeAll { $0.source.lowercased() == target }
            try manifestStore.saveManifest(manifest)
            var lock = manifestStore.currentLock
            lock.plugins.removeAll { $0.source.lowercased() == target }
            try manifestStore.saveLock(lock)
            return
        }
        throw PluginsManagerError.unknownSource(source)
    }

    /// Remove a plugin: delete the bundle from disk, then drop the entry from manifest + lock + registry.
    /// Bundle removal runs first so a permission error leaves the runtime state recoverable.
    /// Local plugins (`isLocal == true`) cannot be removed via this path — they are not managed by plugins.yml.
    /// `async` so it can wait for an in-flight `add()` to finish before mutating the manifest.
    func remove(pluginID: String) async throws {
        try await serializeMutation { [self] in
            try unsafeRemove(pluginID: pluginID)
        }
    }

    private func unsafeRemove(pluginID: String) throws {
        guard let record = pluginStore.record(forID: pluginID) else {
            throw PluginsManagerError.unknownPlugin(pluginID)
        }
        if record.isLocal {
            throw PluginsManagerError.localPluginNotManaged(pluginID)
        }
        guard let source = PluginsManifestEntry.source(fromGitHubURL: record.githubURL) else {
            throw PluginsManagerError.unknownPlugin(pluginID)
        }

        // Delete bundle + registry record first (this can throw).
        try installer.uninstall(pluginID: pluginID)
        // Only then tear down the live widgets and update the manifest/lock files.
        DylibPluginLoader.shared.markForRemoval(pluginID: pluginID, from: WidgetRegistry.shared)

        // Case-insensitive match: plugins.yml may have been hand-edited with a different
        // casing than the registry's githubURL. Without this, the bundle is gone but the
        // manifest entry survives, and next sync re-installs the plugin.
        let target = source.lowercased()
        var manifest = manifestStore.currentManifest
        manifest.plugins.removeAll { $0.source.lowercased() == target }
        try manifestStore.saveManifest(manifest)

        var lock = manifestStore.currentLock
        lock.plugins.removeAll { $0.source.lowercased() == target }
        try manifestStore.saveLock(lock)
    }

    // MARK: - Mutation serialization

    /// Run `work` after any prior add/remove/sync finishes. Prevents races where one mutator
    /// yields on a GitHub download while a sibling mutator writes the manifest/lock from a stale
    /// snapshot. The await chain is placed *inside* the new task body — not in the caller — so
    /// two callers queued behind the same predecessor still serialize against each other when
    /// the predecessor completes.
    private func serializeMutation<T: Sendable>(
        _ work: @MainActor @escaping () async throws -> T
    ) async throws -> T {
        let previous = mutationTail
        let task = Task<T, any Error> { @MainActor in
            _ = await previous?.value
            return try await work()
        }
        // The tail erases the result type and ignores errors so a failed predecessor
        // never blocks the queue.
        mutationTail = Task<Void, Never> { _ = try? await task.value }
        return try await task.value
    }

    // MARK: - Manifest DTOs (for IPC)

    /// Snapshot suitable for the `pluginsList` IPC response.
    func manifestEntryDTOs() -> [PluginManifestEntryDTO] {
        let manifest = manifestStore.currentManifest
        let lock = manifestStore.currentLock
        return manifest.plugins.map { entry in
            let lockEntry = lock.plugins.first { $0.source == entry.source }
            return PluginManifestEntryDTO(
                source: entry.source,
                declaredVersion: entry.version,
                resolvedVersion: lockEntry?.resolvedVersion,
                zipSHA256: lockEntry?.zipSHA256,
                pluginID: lockEntry?.pluginID
            )
        }
    }

    // MARK: - Private

    /// Outcome of applying a single manifest entry during sync.
    private struct EntryOutcome {
        enum Action { case skipped, installed, updated }
        let lockEntry: PluginsLockEntry
        let record: InstalledPluginRecord
        let action: Action
    }

    /// Resolve a single manifest entry, installing or skipping as needed.
    private func applyEntry(
        _ entry: PluginsManifestEntry,
        lock: PluginsLock,
        frozen: Bool
    ) async throws -> EntryOutcome {
        guard let (owner, repo) = entry.parseGitHubSource() else {
            throw PluginsManifestError.invalidSource(entry.source)
        }
        let sourceURL = "https://github.com/\(owner)/\(repo)"
        let existingLock = lock.plugins.first { $0.source == entry.source }

        if frozen {
            return try await applyFromLock(entry: entry, existingLock: existingLock, sourceURL: sourceURL)
        }

        // Decide the target version.
        let targetVersion: String = if entry.isLatest {
            try await installer.latestTagName(owner: owner, repo: repo)
        } else {
            GitHubPluginInstaller.normalizeVersion(entry.version)
        }

        // Skip when registry + lock already match the resolved version.
        if let existingLock,
           let record = upToDateRecord(for: existingLock, targetVersion: targetVersion)
        {
            return EntryOutcome(lockEntry: existingLock, record: record, action: .skipped)
        }

        let installVersion: String? = entry.isLatest ? nil : entry.version
        let install = try await installer.install(from: sourceURL, version: installVersion)

        let lockEntry = PluginsLockEntry(
            source: entry.source,
            resolvedVersion: install.record.version,
            pluginID: install.record.id,
            bundleName: install.record.bundleName,
            assetURL: install.assetURL,
            zipSHA256: install.zipSHA256,
            resolvedAt: Date()
        )
        let action: EntryOutcome.Action = existingLock == nil ? .installed : .updated
        return EntryOutcome(lockEntry: lockEntry, record: install.record, action: action)
    }

    /// Return the registry record matching a lock entry when the installed copy is already at the
    /// target version and the lock has the asset/SHA needed for future frozen-mode restores.
    private func upToDateRecord(
        for lockEntry: PluginsLockEntry,
        targetVersion: String
    ) -> InstalledPluginRecord? {
        guard lockEntry.resolvedVersion == targetVersion,
              lockEntry.assetURL != nil,
              lockEntry.zipSHA256 != nil,
              let record = pluginStore.record(forID: lockEntry.pluginID),
              GitHubPluginInstaller.normalizeVersion(record.version) == targetVersion
        else {
            return nil
        }
        return record
    }

    /// Frozen-mode application: resolve strictly from the lockfile and verify the SHA-256.
    private func applyFromLock(
        entry: PluginsManifestEntry,
        existingLock: PluginsLockEntry?,
        sourceURL: String
    ) async throws -> EntryOutcome {
        guard let lockEntry = existingLock else {
            throw PluginsManagerError.frozenMissingLockEntry(entry.source)
        }
        guard let assetURL = lockEntry.assetURL, let expectedSHA = lockEntry.zipSHA256 else {
            throw PluginsManagerError.frozenIncompleteLockEntry(entry.source)
        }

        if let record = pluginStore.record(forID: lockEntry.pluginID),
           GitHubPluginInstaller.normalizeVersion(record.version) == lockEntry.resolvedVersion
        {
            return EntryOutcome(lockEntry: lockEntry, record: record, action: .skipped)
        }

        let record = try await installer.installFromLock(
            sourceURL: sourceURL,
            assetURL: assetURL,
            expectedSHA256: expectedSHA,
            resolvedVersion: lockEntry.resolvedVersion
        )
        return EntryOutcome(lockEntry: lockEntry, record: record, action: .installed)
    }

    // MARK: - External edit handling

    private func handleExternalEdit() {
        do {
            try manifestStore.reload()
            isDirty = true
            ToastManager.shared.post(ToastRequest(
                title: "plugins.yml changed",
                message: "Run 'Sync Plugins' to apply",
                icon: "doc.badge.gearshape",
                level: .info,
                duration: 6
            ))
        } catch {
            // Don't update isDirty — the old in-memory manifest is still valid; surface the parse error.
            logger.error("Failed to reload plugins.yml: \(error.localizedDescription)")
            ToastManager.shared.post(ToastRequest(
                title: "plugins.yml has a parse error",
                message: error.localizedDescription,
                icon: "exclamationmark.triangle",
                level: .warning,
                duration: 8
            ))
        }
    }
}

// MARK: - PluginsManagerError

enum PluginsManagerError: Error, LocalizedError {
    case unknownPlugin(String)
    case unknownSource(String)
    case localPluginNotManaged(String)
    case frozenMissingLockEntry(String)
    case frozenIncompleteLockEntry(String)

    var errorDescription: String? {
        switch self {
        case let .unknownPlugin(id):
            "Unknown plugin: \(id)"
        case let .unknownSource(source):
            "No installed plugin matches source \(source)"
        case let .localPluginNotManaged(id):
            "Local plugin \(id) is not managed by plugins.yml"
        case let .frozenMissingLockEntry(source):
            "frozen sync: no lockfile entry for \(source) — run a regular sync first"
        case let .frozenIncompleteLockEntry(source):
            "frozen sync: lockfile entry for \(source) is missing asset URL or checksum — run a regular sync first"
        }
    }
}
