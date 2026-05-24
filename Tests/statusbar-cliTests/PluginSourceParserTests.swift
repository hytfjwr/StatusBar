@testable import sbar
import Testing

struct PluginSourceParserTests {
    @Test
    func `owner-slash-repo is normalized to github prefix`() throws {
        #expect(try PluginSourceParser.normalize("acme/foo-widget") == "github:acme/foo-widget")
    }

    @Test
    func `github prefix passes through unchanged`() throws {
        #expect(try PluginSourceParser.normalize("github:acme/foo-widget") == "github:acme/foo-widget")
    }

    @Test
    func `https URL is normalized`() throws {
        #expect(try PluginSourceParser.normalize("https://github.com/acme/foo-widget") == "github:acme/foo-widget")
    }

    @Test
    func `https URL with extra path segments is normalized to owner-repo`() throws {
        // `gh repo view <url>` style URLs sometimes include /tree/main — accept and ignore the tail.
        #expect(
            try PluginSourceParser.normalize("https://github.com/acme/foo-widget/tree/main") == "github:acme/foo-widget"
        )
    }

    @Test
    func `whitespace is trimmed before parsing`() throws {
        #expect(try PluginSourceParser.normalize("  acme/foo-widget  ") == "github:acme/foo-widget")
    }

    @Test
    func `empty input throws`() {
        #expect(throws: PluginSourceParser.ParseError.self) {
            try PluginSourceParser.normalize("")
        }
    }

    @Test
    func `missing slash throws`() {
        #expect(throws: PluginSourceParser.ParseError.self) {
            try PluginSourceParser.normalize("acme")
        }
    }

    @Test
    func `leading dot in owner is rejected as path traversal`() {
        // Mirrors the app-side regex that excludes `.` and `..` to keep plugins.yml from pointing
        // at parent directories or non-repo paths.
        #expect(throws: PluginSourceParser.ParseError.self) {
            try PluginSourceParser.normalize(".acme/foo")
        }
    }

    @Test
    func `empty repo segment is rejected`() {
        #expect(throws: PluginSourceParser.ParseError.self) {
            try PluginSourceParser.normalize("acme/")
        }
    }

    @Test
    func `dots and dashes inside segments are accepted`() throws {
        #expect(try PluginSourceParser.normalize("a-co/foo.bar_baz-2") == "github:a-co/foo.bar_baz-2")
    }

    @Test
    func `clone URL .git suffix is stripped to match the registry record`() throws {
        // Without stripping, sync()'s drift check sees `github:acme/foo` on the registry vs
        // `github:acme/foo.git` in the manifest and uninstalls+reinstalls every run.
        #expect(try PluginSourceParser.normalize("https://github.com/acme/foo.git") == "github:acme/foo")
        #expect(try PluginSourceParser.normalize("acme/foo.git") == "github:acme/foo")
        #expect(try PluginSourceParser.normalize("github:acme/foo.git") == "github:acme/foo")
    }

    @Test
    func `http URL is also accepted`() throws {
        #expect(try PluginSourceParser.normalize("http://github.com/acme/foo") == "github:acme/foo")
    }
}
