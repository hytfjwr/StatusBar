import AppKit
@testable import StatusBar
import SwiftUI
import Testing

/// System appearance resolution and the text colors derived from it.
@MainActor
struct AppearanceTests {

    // MARK: - Appearance Resolution

    @Test("Base appearances resolve to the matching flag")
    func baseAppearances() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))
        #expect(AppearanceService.isDark(dark))
        #expect(!AppearanceService.isDark(light))
    }

    /// `bestMatch` must collapse the vibrant variants onto their base appearance —
    /// popups and glass views run vibrant, and treating them as neither would
    /// silently fall back to light colors on a dark bar.
    @Test("Vibrant variants collapse onto their base appearance")
    func vibrantVariants() throws {
        let vibrantDark = try #require(NSAppearance(named: .vibrantDark))
        let vibrantLight = try #require(NSAppearance(named: .vibrantLight))
        #expect(AppearanceService.isDark(vibrantDark))
        #expect(!AppearanceService.isDark(vibrantLight))
    }

    @Test("Increased-contrast dark variant resolves to dark")
    func increasedContrastDark() throws {
        let contrastDark = try #require(NSAppearance(named: .accessibilityHighContrastDarkAqua))
        #expect(AppearanceService.isDark(contrastDark))
    }

    // MARK: - Derived Text Colors

    @Test("Text color flips between white and black with the appearance")
    func textColorFollowsAppearance() {
        #expect(PreferencesModel.textColor(isDark: true, opacity: 1).toHex() == 0xFFFFFF)
        #expect(PreferencesModel.textColor(isDark: false, opacity: 1).toHex() == 0x000000)
    }

    /// The opacity preferences only dim the text; they must not shift the base color.
    @Test("Reduced opacity keeps the base color")
    func textColorKeepsBaseAtLowOpacity() {
        #expect(PreferencesModel.textColor(isDark: true, opacity: 0.3).toHex() == 0xFFFFFF)
        #expect(PreferencesModel.textColor(isDark: false, opacity: 0.3).toHex() == 0x000000)
    }
}
