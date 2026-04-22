import Foundation
@testable import StatusBar
import Testing
import Yams

// MARK: - FixScientificNotationTests

struct FixScientificNotationTests {
    @Test("Converts positive exponent to integer")
    func positiveExponentInteger() {
        let input = "height: 4e+1"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "height: 40")
    }

    @Test("Converts negative exponent to decimal")
    func negativeExponentDecimal() {
        let input = "opacity: 5.5e-1"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "opacity: 0.55")
    }

    @Test("Converts zero exponent")
    func zeroExponent() {
        let input = "value: 1.5e0"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "value: 1.5")
    }

    @Test("Handles multiple occurrences in same string")
    func multipleOccurrences() {
        let input = "a: 4e+1\nb: 1.2e+2\nc: 5e-1"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result.contains("a: 40"))
        #expect(result.contains("b: 120"))
        #expect(result.contains("c: 0.5"))
    }

    @Test("Leaves non-scientific values unchanged")
    func nonScientificUnchanged() {
        let input = "height: 44\nopacity: 0.75\nname: hello"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == input)
    }

    @Test("Handles uppercase E notation")
    func uppercaseE() {
        let input = "value: 3.5E+2"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "value: 350")
    }

    @Test("Handles negative base value")
    func negativeBase() {
        let input = "offset: -2.5e+1"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "offset: -25")
    }

    @Test("Preserves trailing decimals when not integer")
    func preservesTrailingDecimals() {
        let input = "value: 1e-1"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "value: 0.1")
    }

    @Test("Handles large integer exponent")
    func largeIntegerExponent() {
        let input = "value: 1e+3"
        let result = ConfigLoader.fixScientificNotation(input)
        #expect(result == "value: 1000")
    }
}

// MARK: - ConfigLoaderBootstrapTests

struct ConfigLoaderBootstrapTests {
    /// Make a unique temp file path under the system temp dir.
    private func tempFileURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("statusbar-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.yml")
    }

    @Test("Parse failure does not overwrite user's config on disk")
    func parseFailurePreservesUserFile() throws {
        let url = tempFileURL()
        let corrupted = "this: is:\n  not: [valid yaml because:\n"
        try Data(corrupted.utf8).write(to: url, options: .atomic)

        let outcome = ConfigLoader.performBootstrapLoad(fileURL: url)

        // Must report parse failure
        guard case let .parseFailed(error) = outcome else {
            Issue.record("Expected .parseFailed outcome, got \(outcome)")
            return
        }
        // The error must not be "file not found" (that would collapse into firstLaunch)
        let nsError = error as NSError
        #expect(!(nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError))

        // File contents must be byte-for-byte identical to what we wrote
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == corrupted)
    }

    @Test("First-launch (file absent) writes a default config to disk")
    func firstLaunchWritesDefault() throws {
        let url = tempFileURL()
        // Ensure file does not exist
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let outcome = ConfigLoader.performBootstrapLoad(fileURL: url)

        guard case .firstLaunch = outcome else {
            Issue.record("Expected .firstLaunch outcome, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        // And the written file must be decodable
        let reloaded = try ConfigLoader.loadConfig(from: url)
        #expect(reloaded.global.bar.height == Double(PreferencesModel.Defaults.barHeight))
    }

    @Test("Existing valid YAML loads without rewriting disk")
    func validFileLoadsCleanly() throws {
        let url = tempFileURL()
        let config = StatusBarConfig()
        try ConfigLoader.writeConfig(config, to: url)
        let before = try Data(contentsOf: url)

        let outcome = ConfigLoader.performBootstrapLoad(fileURL: url)

        guard case .loaded = outcome else {
            Issue.record("Expected .loaded outcome, got \(outcome)")
            return
        }
        let after = try Data(contentsOf: url)
        #expect(before == after)
    }
}
