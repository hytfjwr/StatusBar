import Foundation
@testable import StatusBar
import Testing

struct ChangelogServiceTests {

    // MARK: - Parse

    @Test("Parses multiple releases from Keep-a-Changelog format")
    func parseMultipleReleases() {
        let input = """
        # Changelog

        ## [0.7.0] - 2026-03-24

        - fix: update popup tint when preferences change (#55)
        - fix: build .app bundle for debug runs (#54)

        ## [0.6.1] - 2026-03-23

        - fix: use Homebrew Cask commands (#52)
        """

        let releases = ChangelogService.parse(input)

        #expect(releases.count == 2)
        #expect(releases[0].version == "0.7.0")
        #expect(releases[0].date == "2026-03-24")
        #expect(releases[0].entries.count == 2)
        #expect(releases[0].entries[0] == "fix: update popup tint when preferences change (#55)")
        #expect(releases[1].version == "0.6.1")
        #expect(releases[1].entries.count == 1)
    }

    @Test("Parses single release")
    func parseSingleRelease() {
        let input = """
        ## [1.0.0] - 2026-01-01

        - feat: initial release
        """

        let releases = ChangelogService.parse(input)

        #expect(releases.count == 1)
        #expect(releases[0].version == "1.0.0")
        #expect(releases[0].entries == ["feat: initial release"])
    }

    @Test("Returns empty array for empty input")
    func parseEmpty() {
        let releases = ChangelogService.parse("")
        #expect(releases.isEmpty)
    }

    @Test("Skips releases with no entries")
    func parseSkipsEmptyReleases() {
        let input = """
        ## [0.5.6] - 2026-03-23

        ## [0.5.5] - 2026-03-23

        - fix: migrate Homebrew distribution (#48)
        """

        let releases = ChangelogService.parse(input)

        #expect(releases.count == 1)
        #expect(releases[0].version == "0.5.5")
    }

    @Test("Ignores non-version headers and preamble")
    func parseIgnoresPreamble() {
        let input = """
        # Changelog

        All notable changes to this project will be documented in this file.

        ## [Unreleased]

        ## [0.3.0] - 2026-03-18

        - feat: first feature
        """

        let releases = ChangelogService.parse(input)

        // [Unreleased] has no date in the expected format, so it is skipped
        #expect(releases.count == 1)
        #expect(releases[0].version == "0.3.0")
    }
}
