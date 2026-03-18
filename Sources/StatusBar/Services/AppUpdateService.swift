import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "AppUpdateService")

// MARK: - AppUpdateService

@MainActor
@Observable
final class AppUpdateService {
    static let shared = AppUpdateService()

    enum UpdateState {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case error(String)
    }

    private(set) var state: UpdateState = .idle

    /// Last time we checked (persisted across launches for auto-check throttling).
    private(set) var lastCheckDate: Date?

    // GitHub repository for this app
    private static let owner = "hytfjwr"
    private static let repo = "StatusBar"

    /// Minimum interval between automatic checks (1 hour).
    private static let autoCheckInterval: TimeInterval = 3_600

    private init() {
        let ts = UserDefaults.standard.double(forKey: "appUpdate.lastCheckTimestamp")
        if ts > 0 {
            lastCheckDate = Date(timeIntervalSince1970: ts)
        }
    }

    // MARK: - Public API

    /// Check for updates. Called manually from UI or automatically on launch.
    func checkForUpdates() async {
        state = .checking

        do {
            let release = try await fetchLatestRelease()
            let latestTag = release.tagName
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            let currentVersion = Self.appVersion

            recordCheck()

            guard let latest = SemanticVersion(latestTag),
                  let current = SemanticVersion(currentVersion)
            else {
                // Fallback to string comparison if parsing fails
                if latestTag != currentVersion {
                    guard let url = URL(string: "https://github.com/\(Self.owner)/\(Self.repo)/releases/latest") else {
                        return
                    }
                    state = .available(version: latestTag, url: url)
                } else {
                    state = .upToDate
                }
                return
            }

            if latest > current {
                guard let url = URL(
                    string: "https://github.com/\(Self.owner)/\(Self.repo)/releases/tag/\(release.tagName)"
                ) else {
                    return
                }
                state = .available(version: latestTag, url: url)
            } else {
                state = .upToDate
            }
        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// Auto-check on launch if enough time has passed.
    func checkIfNeeded() async {
        if let last = lastCheckDate,
           Date().timeIntervalSince(last) < Self.autoCheckInterval
        {
            return
        }
        await checkForUpdates()
    }

    // MARK: - Version

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Private

    private func recordCheck() {
        let now = Date()
        lastCheckDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "appUpdate.lastCheckTimestamp")
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.networkError
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.networkError
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw UpdateError.rateLimited
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.noRelease
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

// MARK: AppUpdateService.UpdateError

extension AppUpdateService {
    enum UpdateError: LocalizedError {
        case networkError
        case rateLimited
        case noRelease

        var errorDescription: String? {
            switch self {
            case .networkError: "Network error"
            case .rateLimited: "GitHub API rate limited. Try again later."
            case .noRelease: "No releases found"
            }
        }
    }
}

// MARK: - GitHubRelease

private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
