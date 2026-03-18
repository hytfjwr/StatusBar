import Foundation
import Testing

@testable import StatusBar

@Suite("GitHubPluginInstaller — URL parsing")
@MainActor
struct GitHubPluginInstallerTests {
    let installer = GitHubPluginInstaller.shared

    // MARK: - parseGitHubURL — valid inputs

    @Test("Parses full HTTPS URL")
    func fullHTTPS() throws {
        let (owner, repo) = try installer.parseGitHubURL("https://github.com/owner/repo")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    @Test("Parses URL with .git suffix")
    func gitSuffix() throws {
        let (owner, repo) = try installer.parseGitHubURL("https://github.com/owner/repo.git")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    @Test("Parses URL without scheme")
    func noScheme() throws {
        let (owner, repo) = try installer.parseGitHubURL("github.com/owner/repo")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    @Test("Parses short owner/repo format")
    func shortFormat() throws {
        let (owner, repo) = try installer.parseGitHubURL("owner/repo")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    @Test("Parses URL with trailing slash")
    func trailingSlash() throws {
        let (owner, repo) = try installer.parseGitHubURL("https://github.com/owner/repo/")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    @Test("Parses HTTP URL")
    func httpURL() throws {
        let (owner, repo) = try installer.parseGitHubURL("http://github.com/owner/repo")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    @Test("Parses URL with extra path segments (ignores extras)")
    func extraPathSegments() throws {
        let (owner, repo) = try installer.parseGitHubURL("https://github.com/owner/repo/releases/latest")
        #expect(owner == "owner")
        #expect(repo == "repo")
    }

    // MARK: - parseGitHubURL — invalid inputs

    @Test("Rejects single component", arguments: [
        "owner",
        "https://github.com/owner",
        "github.com/owner",
    ])
    func rejectsSingleComponent(url: String) {
        #expect(throws: GitHubPluginError.self) {
            try installer.parseGitHubURL(url)
        }
    }

    @Test("Rejects empty string")
    func rejectsEmpty() {
        #expect(throws: GitHubPluginError.self) {
            try installer.parseGitHubURL("")
        }
    }

    // MARK: - needsUpdate — version comparison

    @Test("Detects update regardless of v prefix format", arguments: [
        // (installed, latestTag, expectedNeedsUpdate)
        ("0.1.0", "v1.0.0", true),    // typical: manifest no-v, tag v-prefixed
        ("v0.1.0", "v1.0.0", true),   // both v-prefixed
        ("0.1.0", "1.0.0", true),     // neither prefixed
    ])
    func detectsUpdate(installed: String, latestTag: String, expected: Bool) {
        #expect(GitHubPluginInstaller.needsUpdate(installed: installed, latestTag: latestTag) == expected)
    }

    @Test("No false update when versions match despite format difference", arguments: [
        // The root cause bug: manifest "v1.0.0" vs tag "v1.0.0" → tag trimmed to "1.0.0"
        // but installed wasn't trimmed, so "v1.0.0" != "1.0.0" showed a phantom update.
        ("1.0.0", "v1.0.0", false),   // registry stores tag-normalized, tag v-prefixed
        ("v1.0.0", "1.0.0", false),   // legacy record with v, tag without
        ("1.0.0", "1.0.0", false),    // identical
        ("V1.0.0", "v1.0.0", false),  // uppercase V
    ])
    func noFalseUpdate(installed: String, latestTag: String, expected: Bool) {
        #expect(GitHubPluginInstaller.needsUpdate(installed: installed, latestTag: latestTag) == expected)
    }
}
