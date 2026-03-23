import Foundation
import StatusBarKit

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
        }
    }
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
    /// The URL should be like: https://github.com/owner/repo
    func install(from urlString: String) async throws -> InstalledPluginRecord { // swiftlint:disable:this function_body_length
        // Parse owner/repo from URL
        let (owner, repo) = try parseGitHubURL(urlString)

        // Fetch latest release
        let release = try await fetchLatestRelease(owner: owner, repo: repo)

        // Find .statusplugin.zip asset
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".statusplugin.zip") }) else {
            throw GitHubPluginError.noPluginAsset
        }

        // Download asset
        let zipData = try await downloadAsset(url: asset.browserDownloadURL)

        // Extract to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipPath = tempDir.appendingPathComponent(asset.name)
        try zipData.write(to: zipPath)

        // Unzip
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
            at: tempDir,
            includingPropertiesForKeys: nil
        )
        guard let pluginBundle = contents.first(where: { $0.pathExtension == "statusplugin" }) else {
            throw GitHubPluginError.manifestMissing
        }

        // Read and validate manifest
        let manifestURL = pluginBundle.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw GitHubPluginError.manifestMissing
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(DylibPluginManifest.self, from: manifestData)

        // Version check
        if let pluginVersion = SemanticVersion(manifest.statusBarKitVersion),
           let hostVersion = SemanticVersion(statusBarKitVersion)
        {
            guard hostVersion.isCompatible(with: pluginVersion) else {
                throw GitHubPluginError.incompatibleVersion(
                    required: manifest.statusBarKitVersion,
                    current: statusBarKitVersion
                )
            }
        }

        // Create plugins directory if needed
        let fm = FileManager.default
        if !fm.fileExists(atPath: pluginsDirectory.path) {
            try fm.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        }

        // Replace plugin bundle on disk (remove old → move new)
        let destURL = pluginsDirectory.appendingPathComponent(pluginBundle.lastPathComponent)
        do { try fm.removeItem(at: destURL) } catch CocoaError.fileNoSuchFile { /* first install */ }
        try fm.moveItem(at: pluginBundle, to: destURL)

        // Use the release tag version for the registry record.
        // checkForUpdates() compares against tag versions, so the registry must
        // store tag-based versions to avoid perpetual "update available" mismatches
        // (manifest version may lag behind the tag if the plugin author forgets to bump it).
        let releaseVersion = Self.normalizeVersion(release.tagName)

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
            return
        }

        let bundleURL = pluginsDirectory.appendingPathComponent("\(record.bundleName).statusplugin")
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }

        try PluginStore.shared.remove(id: pluginID)
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
                print("[GitHubPluginInstaller] Update check failed for \(plugin.name): \(error.localizedDescription)")
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

    private func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw GitHubPluginError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubPluginError.noReleaseFound
        }

        // Distinguish rate limiting from "no release"
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw GitHubPluginError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubPluginError.noReleaseFound
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func downloadAsset(url: String) async throws -> Data {
        guard let downloadURL = URL(string: url) else {
            throw GitHubPluginError.downloadFailed
        }

        // Validate URL host and scheme to prevent SSRF
        guard downloadURL.scheme == "https",
              let host = downloadURL.host,
              Self.allowedDownloadHosts.contains(host)
        else {
            throw GitHubPluginError.untrustedDownloadURL(url)
        }

        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
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
