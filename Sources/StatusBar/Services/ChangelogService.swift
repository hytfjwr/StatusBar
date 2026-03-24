import Foundation
import OSLog

private let logger = Logger(subsystem: "com.statusbar", category: "ChangelogService")

// MARK: - ChangelogRelease

struct ChangelogRelease: Identifiable {
    var id: String {
        version
    }

    let version: String
    let date: String
    let entries: [String]
}

// MARK: - ChangelogService

@MainActor
@Observable
final class ChangelogService {
    static let shared = ChangelogService()

    enum FetchState {
        case idle
        case loading
        case loaded([ChangelogRelease])
        case failed(String)
    }

    private(set) var state: FetchState = .idle

    private static let changelogURL = URL(
        string: "https://raw.githubusercontent.com/hytfjwr/StatusBar/main/CHANGELOG.md"
    )!

    static let githubChangelogURL = URL(
        string: "https://github.com/hytfjwr/StatusBar/blob/main/CHANGELOG.md"
    )!

    private init() {}

    // MARK: - Public API

    func fetchIfNeeded() async {
        guard case .idle = state else {
            return
        }
        state = .loading

        do {
            let releases = try await Self.fetchAndParse()
            state = .loaded(releases)
        } catch {
            logger.warning("Changelog fetch failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func fetchAndParse() async throws -> [ChangelogRelease] {
        let (data, _) = try await URLSession.shared.data(from: changelogURL)
        let text = String(decoding: data, as: UTF8.self)
        return parse(text)
    }

    func retry() async {
        state = .idle
        await fetchIfNeeded()
    }

    func release(for version: String) -> ChangelogRelease? {
        guard case let .loaded(releases) = state else {
            return nil
        }
        let normalized = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return releases.first { $0.version == normalized }
    }

    // MARK: - Parser

    nonisolated static func parse(_ text: String) -> [ChangelogRelease] {
        let versionPattern = /^## \[(?<version>[^\]]+)\] - (?<date>.+)$/

        var releases: [ChangelogRelease] = []
        var currentVersion: String?
        var currentDate: String?
        var currentEntries: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let match = line.wholeMatch(of: versionPattern) {
                // Flush previous release
                if let version = currentVersion, let date = currentDate, !currentEntries.isEmpty {
                    releases.append(ChangelogRelease(
                        version: version, date: date, entries: currentEntries
                    ))
                }
                currentVersion = String(match.version)
                currentDate = String(match.date)
                currentEntries = []
            } else if line.hasPrefix("- ") {
                currentEntries.append(String(line.dropFirst(2)))
            }
        }

        // Flush last release
        if let version = currentVersion, let date = currentDate, !currentEntries.isEmpty {
            releases.append(ChangelogRelease(
                version: version, date: date, entries: currentEntries
            ))
        }

        return releases
    }
}
