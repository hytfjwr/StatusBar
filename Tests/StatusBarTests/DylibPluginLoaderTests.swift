import Foundation
import StatusBarKit
import Testing

@testable import StatusBar

@Suite("DylibPluginLoader — manifest validation")
@MainActor
struct DylibPluginLoaderTests {
    let loader = DylibPluginLoader.shared

    // MARK: - Valid manifests

    @Test("Accepts valid manifest with alphanumeric id")
    func validManifest() throws {
        let manifest = DylibPluginManifest(
            id: "com.example.my-plugin",
            name: "My Plugin",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2"
        )
        try loader.validateManifestFields(manifest)
    }

    @Test("Accepts manifest with dots, hyphens, underscores in id")
    func validIDCharacters() throws {
        let manifest = DylibPluginManifest(
            id: "com.example_test.plugin-v2",
            name: "Test Plugin",
            version: "2.1.0-beta",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2"
        )
        try loader.validateManifestFields(manifest)
    }

    // MARK: - Invalid IDs

    @Test("Rejects id with spaces")
    func rejectsIDWithSpaces() {
        let manifest = DylibPluginManifest(
            id: "my plugin",
            name: "My Plugin",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2"
        )
        #expect(throws: PluginLoadError.self) {
            try loader.validateManifestFields(manifest)
        }
    }

    @Test("Rejects id with special characters")
    func rejectsIDWithSpecialChars() {
        let manifest = DylibPluginManifest(
            id: "plugin@v1",
            name: "My Plugin",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2"
        )
        #expect(throws: PluginLoadError.self) {
            try loader.validateManifestFields(manifest)
        }
    }

    @Test("Rejects id with path traversal")
    func rejectsIDWithPathTraversal() {
        let manifest = DylibPluginManifest(
            id: "../../../etc/passwd",
            name: "Evil Plugin",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2"
        )
        #expect(throws: PluginLoadError.self) {
            try loader.validateManifestFields(manifest)
        }
    }

    // MARK: - Invalid entry symbols

    @Test("Rejects entry symbol starting with digit")
    func rejectsSymbolStartingWithDigit() {
        let manifest = DylibPluginManifest(
            id: "valid-id",
            name: "My Plugin",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2",
            entrySymbol: "1createPlugin"
        )
        #expect(throws: PluginLoadError.self) {
            try loader.validateManifestFields(manifest)
        }
    }

    @Test("Rejects entry symbol with special characters")
    func rejectsSymbolWithSpecialChars() {
        let manifest = DylibPluginManifest(
            id: "valid-id",
            name: "My Plugin",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2",
            entrySymbol: "create-plugin"
        )
        #expect(throws: PluginLoadError.self) {
            try loader.validateManifestFields(manifest)
        }
    }

    // MARK: - Invalid names

    @Test("Rejects name with shell injection characters")
    func rejectsNameWithShellInjection() {
        let manifest = DylibPluginManifest(
            id: "valid-id",
            name: "Plugin; rm -rf /",
            version: "1.0.0",
            statusBarKitVersion: "1.0.0",
            swiftVersion: "6.2"
        )
        #expect(throws: PluginLoadError.self) {
            try loader.validateManifestFields(manifest)
        }
    }
}
