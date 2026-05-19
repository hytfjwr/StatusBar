import CryptoKit
import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "GitHubPluginInstaller")

// MARK: - GitHubPluginError

enum GitHubPluginError: Error, LocalizedError {
    case invalidURL(String)
    case networkError(any Error)
    case noReleaseFound
    case noPluginAsset
    case downloadFailed
    case extractionFailed(any Error)
    case manifestMissing
    case incompatibleVersion(required: String, current: String)
    case untrustedDownloadURL(String)
    case rateLimited
    case zipSHA256Mismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "Invalid GitHub URL: \(url)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .noReleaseFound:
            "No releases found for this repository"
        case .noPluginAsset:
            "No .statusplugin.zip asset found in the latest release"
        case .downloadFailed:
            "Failed to download plugin asset"
        case let .extractionFailed(error):
            "Failed to extract plugin: \(error.localizedDescription)"
        case .manifestMissing:
            "Downloaded plugin does not contain a valid manifest.json"
        case let .incompatibleVersion(required, current):
            "Plugin requires StatusBarKit \(required), but app has \(current)"
        case let .untrustedDownloadURL(url):
            "Download URL is not from a trusted GitHub domain: \(url)"
        case .rateLimited:
            "GitHub API rate limit exceeded. Try again later or configure a personal access token."
        case let .zipSHA256Mismatch(expected, actual):
            "Lockfile SHA-256 mismatch — expected \(expected), got \(actual)"
        }
    }
}

// MARK: - InstallResult

/// Detailed outcome of an install. Carries the resolved zip hash and download URL so the
/// caller (`PluginsManager`) can update plugins-lock.yml.
struct InstallResult {
    let record: InstalledPluginRecord
    /// SHA-256 of the downloaded .statusplugin.zip (hex, lowercase).
    let zipSHA256: String
    /// URL the zip was downloaded from (typically objects.githubusercontent.com).
    let assetURL: String
}

// MARK: - GitHubPluginInstaller

@MainActor
final class GitHubPluginInstaller {
    static let shared = GitHubPluginInstaller()

    private init() {}

    /// Trusted download hosts for SSRF prevention
    private static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
    ]

    private var pluginsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar/plugins")
    }

    // MARK: - Install

    /// Install a plugin from a GitHub repository URL.
    /// - Parameters:
    ///   - urlString: A repository URL like `https://github.com/owner/repo`.
    ///   - version: A specific release tag (e.g. `"1.2.0"`) or `nil` / `"latest"` for the latest release.
    func install(from urlString: String, version: String? = nil) async throws -> InstallResult {
        let (owner, repo) = try parseGitHubURL(urlString)
        logger.info("Installing plugin from \(owner)/\(repo) (version: \(version ?? "latest"))")

        let release: GitHubRelease = if let version, version != "latest" {
            try await fetchRelease(owner: owner, repo: repo, tag: version)
        } else {
            try await fetchLatestRelease(owner: owner, repo: repo)
        }
        logger.info("Found release \(release.tagName) for \(owner)/\(repo)")

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".statusplugin.zip") }) else {
            logger.error("No .statusplugin.zip asset in release \(release.tagName) for \(owner)/\(repo)")
            throw GitHubPluginError.noPluginAsset
        }

        let zipData = try await downloadAsset(url: asset.browserDownloadURL)
        logger.info("Downloaded \(asset.name) (\(zipData.count) bytes)")
        let zipSHA256 = Self.hexHash(of: zipData)

        let releaseVersion = Self.normalizeVersion(release.tagName)
        let record = try await installFromZipData(
            zipData: zipData,
            assetName: asset.name,
            owner: owner,
            repo: repo,
            resolvedVersion: releaseVersion
        )

        return InstallResult(record: record, zipSHA256: zipSHA256, assetURL: asset.browserDownloadURL)
    }

    /// Install (or re-install) a plugin using a lockfile entry. Downloads from the recorded
    /// asset URL and verifies the SHA-256 before placing the bundle on disk.
    func installFromLock(
        sourceURL: String,
        assetURL: String,
        expectedSHA256: String,
        resolvedVersion: String
    ) async throws -> InstalledPluginRecord {
        let (owner, repo) = try parseGitHubURL(sourceURL)
        logger.info("Restoring \(owner)/\(repo) @ \(resolvedVersion) from lockfile")

        let zipData = try await downloadAsset(url: assetURL)
        let actualSHA = Self.hexHash(of: zipData)
        guard actualSHA == expectedSHA256.lowercased() else {
            logger.error("SHA-256 mismatch for \(owner)/\(repo) — expected \(expectedSHA256), got \(actualSHA)")
            throw GitHubPluginError.zipSHA256Mismatch(expected: expectedSHA256, actual: actualSHA)
        }

        // Asset name is unused beyond logging; derive a reasonable label from the URL.
        let assetName = URL(string: assetURL)?.lastPathComponent ?? "plugin.statusplugin.zip"
        return try await installFromZipData(
            zipData: zipData,
            assetName: assetName,
            owner: owner,
            repo: repo,
            resolvedVersion: resolvedVersion
        )
    }

    /// Shared install pipeline: extract, validate, place on disk, register in the store.
    private func installFromZipData(
        zipData: Data,
        assetName: String,
        owner: String,
        repo: String,
        resolvedVersion: String
    ) async throws -> InstalledPluginRecord {
        let (pluginBundle, tempDir) = try await extractAndValidate(zipData: zipData, assetName: assetName)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifest = try readAndValidateManifest(in: pluginBundle)
        let destURL = try placeBundle(pluginBundle, in: pluginsDirectory)
        let record = try registerRecord(
            manifest: manifest, destURL: destURL,
            owner: owner, repo: repo, releaseVersion: resolvedVersion
        )
        logger.info("Installed plugin \(manifest.name) v\(resolvedVersion)")
        return record
    }

    /// SHA-256 of a blob as a lowercase hex string.
    static func hexHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Extract zip data to a temp directory and validate the extracted contents.
    /// Returns the plugin bundle URL and the temp directory (caller must clean up).
    private func extractAndValidate(zipData: Data, assetName: String) async throws -> (URL, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipPath = tempDir.appendingPathComponent(assetName)
        try zipData.write(to: zipPath)
        try await unzip(zipPath, to: tempDir)

        // Validate no path traversal in extracted files
        let extractedPaths = try FileManager.default.subpathsOfDirectory(atPath: tempDir.path)
        let resolvedTempDir = tempDir.standardizedFileURL.path
        for subpath in extractedPaths {
            let fullPath = tempDir.appendingPathComponent(subpath).standardizedFileURL.path
            guard fullPath.hasPrefix(resolvedTempDir) else {
                throw GitHubPluginError.extractionFailed(
                    NSError(domain: "unzip", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Path traversal detected in archive: \(subpath)",
                    ])
                )
            }
        }

        // Find the .statusplugin directory
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        )
        guard let pluginBundle = contents.first(where: { $0.pathExtension == "statusplugin" }) else {
            logger.error("No .statusplugin bundle found in extracted archive")
            throw GitHubPluginError.manifestMissing
        }

        return (pluginBundle, tempDir)
    }

    /// Read manifest.json from the plugin bundle and check version compatibility.
    private func readAndValidateManifest(in pluginBundle: URL) throws -> DylibPluginManifest {
        let manifestURL = pluginBundle.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            logger.error("manifest.json not found in \(pluginBundle.lastPathComponent)")
            throw GitHubPluginError.manifestMissing
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: DylibPluginManifest
        do {
            manifest = try JSONDecoder().decode(DylibPluginManifest.self, from: manifestData)
        } catch {
            logger.error("Failed to decode manifest in \(pluginBundle.lastPathComponent): \(error.localizedDescription)")
            throw error
        }

        if let pluginVersion = SemanticVersion(manifest.statusBarKitVersion),
           let hostVersion = SemanticVersion(statusBarKitVersion)
        {
            guard hostVersion.isCompatible(with: pluginVersion) else {
                let required = manifest.statusBarKitVersion
                logger.error(
                    "Incompatible StatusBarKit for \(manifest.name): requires \(required), app has \(statusBarKitVersion)"
                )
                throw GitHubPluginError.incompatibleVersion(
                    required: manifest.statusBarKitVersion,
                    current: statusBarKitVersion
                )
            }
        }

        return manifest
    }

    /// Move the plugin bundle to the plugins directory, replacing any existing version.
    private func placeBundle(_ pluginBundle: URL, in pluginsDirectory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        let destURL = pluginsDirectory.appendingPathComponent(pluginBundle.lastPathComponent)
        do { try fm.removeItem(at: destURL) } catch CocoaError.fileNoSuchFile { /* first install */ }
        try fm.moveItem(at: pluginBundle, to: destURL)
        return destURL
    }

    /// Create or update the plugin store record.
    private func registerRecord(
        manifest: DylibPluginManifest,
        destURL: URL,
        owner: String,
        repo: String,
        releaseVersion: String
    ) throws -> InstalledPluginRecord {
        // Use the release tag version for the registry record.
        // checkForUpdates() compares against tag versions, so the registry must
        // store tag-based versions to avoid perpetual "update available" mismatches
        // (manifest version may lag behind the tag if the plugin author forgets to bump it).
        let normalizedURL = "https://github.com/\(owner)/\(repo)"
        let bundleName = destURL.deletingPathExtension().lastPathComponent
        let store = PluginStore.shared
        let record: InstalledPluginRecord = if let existing = store.record(forID: manifest.id, orBundleName: bundleName) {
            existing.updating(
                name: manifest.name,
                version: releaseVersion,
                githubURL: normalizedURL
            )
        } else {
            InstalledPluginRecord(
                id: manifest.id,
                name: manifest.name,
                version: releaseVersion,
                githubURL: normalizedURL,
                bundleName: bundleName
            )
        }
        try store.add(record)
        return record
    }

    // MARK: - Uninstall

    /// Remove a plugin by ID.
    func uninstall(pluginID: String) throws {
        guard let record = PluginStore.shared.record(forID: pluginID) else {
            logger.warning("Uninstall requested for unknown plugin ID: \(pluginID)")
            return
        }

        logger.info("Uninstalling plugin \(record.name) (\(pluginID))")

        let bundleURL = pluginsDirectory.appendingPathComponent("\(record.bundleName).statusplugin")
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }

        try PluginStore.shared.remove(id: pluginID)
        logger.info("Uninstalled plugin \(record.name)")
    }

    // MARK: - Update Check

    struct UpdateInfo {
        let pluginID: String
        let currentVersion: String
        let latestVersion: String
        let githubURL: String
    }

    /// Check all installed plugins for available updates.
    func checkForUpdates() async -> [UpdateInfo] {
        var updates: [UpdateInfo] = []

        for plugin in PluginStore.shared.plugins {
            guard let url = plugin.githubURL else {
                continue
            }
            do {
                let (owner, repo) = try parseGitHubURL(url)
                let release = try await fetchLatestRelease(owner: owner, repo: repo)
                let latestVersion = Self.normalizeVersion(release.tagName)
                let currentVersion = Self.normalizeVersion(plugin.version)
                if Self.needsUpdate(installed: plugin.version, latestTag: release.tagName) {
                    updates.append(UpdateInfo(
                        pluginID: plugin.id,
                        currentVersion: currentVersion,
                        latestVersion: latestVersion,
                        githubURL: url
                    ))
                }
            } catch {
                logger.warning("Update check failed for \(plugin.name): \(error.localizedDescription)")
            }
        }

        return updates
    }

    // MARK: - Version Helpers

    /// Strip leading "v"/"V" prefix from version strings for consistent comparison.
    /// Both release tags ("v1.0.0") and manifest versions ("1.0.0" or "v1.0.0") are normalized.
    static func normalizeVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    /// Whether an update is available (strict greater-than to avoid treating downgrades as updates).
    static func needsUpdate(installed: String, latestTag: String) -> Bool {
        let installedNorm = normalizeVersion(installed)
        let latestNorm = normalizeVersion(latestTag)
        if let installedVer = SemanticVersion(installedNorm),
           let latestVer = SemanticVersion(latestNorm)
        {
            return latestVer > installedVer
        }
        // Fallback to string comparison for non-semver versions
        return latestNorm != installedNorm
    }

    // MARK: - Private

    /// GitHub owner/repo name pattern: must start with alphanumeric, rest allows hyphens, dots, underscores.
    /// Rejects "." and ".." (path traversal).
    private static let ownerRepoPattern = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/

    func parseGitHubURL(_ urlString: String) throws -> (owner: String, repo: String) {
        // Handle formats:
        //   https://github.com/owner/repo
        //   https://github.com/owner/repo.git
        //   github.com/owner/repo
        //   owner/repo
        var cleaned = urlString

        if let components = URLComponents(string: urlString), components.scheme != nil {
            guard let host = components.host, host == "github.com" else {
                throw GitHubPluginError.invalidURL(urlString)
            }
            cleaned = components.path
            if cleaned.hasPrefix("/") {
                cleaned = String(cleaned.dropFirst())
            }
        } else {
            if cleaned.hasPrefix("github.com/") {
                cleaned = String(cleaned.dropFirst("github.com/".count))
            }
        }

        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(4))
        }
        // Remove trailing slash
        if cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }

        let parts = cleaned.split(separator: "/")
        guard parts.count >= 2 else {
            throw GitHubPluginError.invalidURL(urlString)
        }

        let owner = String(parts[0])
        let repo = String(parts[1])

        guard owner.wholeMatch(of: Self.ownerRepoPattern) != nil,
              repo.wholeMatch(of: Self.ownerRepoPattern) != nil
        else {
            throw GitHubPluginError.invalidURL(urlString)
        }

        return (owner: owner, repo: repo)
    }

    /// Resolve the latest release tag (normalized — no `v` prefix) without downloading the asset.
    /// Used by `PluginsManager` to short-circuit sync when `plugins.yml` declares `version: latest`
    /// but the lockfile already references the same tag.
    func latestTagName(owner: String, repo: String) async throws -> String {
        let release = try await fetchLatestRelease(owner: owner, repo: repo)
        return Self.normalizeVersion(release.tagName)
    }

    /// Fetch a specific release by its tag name. Tries the tag verbatim and, if not found,
    /// falls back to the `v`-prefixed form (handles `1.2.0` vs `v1.2.0` interchangeably).
    private func fetchRelease(owner: String, repo: String, tag: String) async throws -> GitHubRelease {
        let candidates: [String] = if tag.hasPrefix("v") || tag.hasPrefix("V") {
            [tag, String(tag.dropFirst())]
        } else {
            [tag, "v\(tag)"]
        }
        var lastError: (any Error)?
        for candidate in candidates {
            do {
                return try await fetchReleaseExact(owner: owner, repo: repo, tag: candidate)
            } catch GitHubPluginError.noReleaseFound {
                lastError = GitHubPluginError.noReleaseFound
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? GitHubPluginError.noReleaseFound
    }

    private func fetchReleaseExact(owner: String, repo: String, tag: String) async throws -> GitHubRelease {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(encoded)"
        guard let url = URL(string: urlString) else {
            throw GitHubPluginError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network request failed for \(owner)/\(repo)@\(tag): \(error.localizedDescription)")
            throw GitHubPluginError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubPluginError.noReleaseFound
        }
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw GitHubPluginError.rateLimited
        }
        guard httpResponse.statusCode == 200 else {
            throw GitHubPluginError.noReleaseFound
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw GitHubPluginError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network request failed for \(owner)/\(repo): \(error.localizedDescription)")
            throw GitHubPluginError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubPluginError.noReleaseFound
        }

        // Distinguish rate limiting from "no release"
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            logger.warning("GitHub API rate limited (HTTP \(httpResponse.statusCode)) for \(owner)/\(repo)")
            throw GitHubPluginError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("GitHub API returned HTTP \(httpResponse.statusCode) for \(owner)/\(repo)")
            throw GitHubPluginError.noReleaseFound
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func downloadAsset(url: String) async throws -> Data {
        guard let downloadURL = URL(string: url) else {
            logger.error("Invalid download URL: \(url)")
            throw GitHubPluginError.downloadFailed
        }

        // Validate URL host and scheme to prevent SSRF
        guard downloadURL.scheme == "https",
              let host = downloadURL.host,
              Self.allowedDownloadHosts.contains(host)
        else {
            logger.error("Untrusted download host rejected: \(downloadURL.host ?? "unknown")")
            throw GitHubPluginError.untrustedDownloadURL(url)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: downloadURL)
        } catch {
            logger.error("Download failed for asset \(downloadURL.lastPathComponent): \(error.localizedDescription)")
            throw GitHubPluginError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Download returned HTTP \(statusCode) for asset \(downloadURL.lastPathComponent)")
            throw GitHubPluginError.downloadFailed
        }
        return data
    }

    private func unzip(_ zipURL: URL, to destination: URL, timeout: TimeInterval = 30) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) let workItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)

            process.terminationHandler = { proc in
                workItem.cancel()
                if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: GitHubPluginError.extractionFailed(
                        NSError(domain: "unzip", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Unzip timed out after \(Int(timeout))s",
                        ])
                    ))
                } else {
                    continuation.resume(returning: proc.terminationStatus)
                }
            }
        }

        guard status == 0 else {
            logger.error("Unzip exited with status \(status) for \(zipURL.lastPathComponent)")
            throw GitHubPluginError.extractionFailed(
                NSError(domain: "unzip", code: Int(status))
            )
        }
    }
}

// MARK: - GitHubRelease

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

// MARK: - GitHubAsset

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
