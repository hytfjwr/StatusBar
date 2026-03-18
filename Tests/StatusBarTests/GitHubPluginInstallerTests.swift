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
}
