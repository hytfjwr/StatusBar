import AppKit
@testable import StatusBar
import SwiftUI
import Testing

/// Clamping behavior tests for `Color.toHex()`.
///
/// Converting a Color initialized in a wide-gamut space like P3 to sRGB can leave components
/// outside [0, 1] (negative values / values > 1.0). Without clamping, `UInt32(x * 255)`
/// crashes on negatives and overflows above 1.0, so verify the clamp works correctly.
struct ColorToHexTests {

    @Test("Pure sRGB red maps to 0xFF0000")
    func pureRed() {
        let color = Color(.sRGB, red: 1, green: 0, blue: 0)
        #expect(color.toHex() == 0xFF0000)
    }

    @Test("Pure sRGB green maps to 0x00FF00")
    func pureGreen() {
        let color = Color(.sRGB, red: 0, green: 1, blue: 0)
        #expect(color.toHex() == 0x00FF00)
    }

    @Test("Pure sRGB blue maps to 0x0000FF")
    func pureBlue() {
        let color = Color(.sRGB, red: 0, green: 0, blue: 1)
        #expect(color.toHex() == 0x0000FF)
    }

    @Test("Black clamps to 0x000000")
    func black() {
        let color = Color(.sRGB, red: 0, green: 0, blue: 0)
        #expect(color.toHex() == 0x000000)
    }

    @Test("White rounds to 0xFFFFFF")
    func white() {
        let color = Color(.sRGB, red: 1, green: 1, blue: 1)
        #expect(color.toHex() == 0xFFFFFF)
    }

    /// Pure displayP3 green sits outside sRGB, so converting to sRGB yields a negative red
    /// component / a green component above 1.0. Without clamping this crashes `UInt32`
    /// initialization, so verify that no crash occurs.
    @Test("Wide-gamut P3 green does not crash and clamps to [0, 0xFF]")
    func p3GreenClamps() {
        let color = Color(.displayP3, red: 0, green: 1, blue: 0)
        let hex = color.toHex()
        // When clamped, each component stays within [0, 0xFF].
        let r = (hex >> 16) & 0xFF
        let g = (hex >> 8) & 0xFF
        let b = hex & 0xFF
        #expect(r <= 0xFF)
        #expect(g <= 0xFF)
        #expect(b <= 0xFF)
        // The green component stays near 1.0 after sRGB conversion, so it should clamp to 0xFF.
        #expect(g == 0xFF)
    }

    @Test("Wide-gamut P3 red does not crash and clamps to [0, 0xFF]")
    func p3RedClamps() {
        let color = Color(.displayP3, red: 1, green: 0, blue: 0)
        let hex = color.toHex()
        let r = (hex >> 16) & 0xFF
        let g = (hex >> 8) & 0xFF
        let b = hex & 0xFF
        #expect(r <= 0xFF)
        #expect(g <= 0xFF)
        #expect(b <= 0xFF)
        #expect(r == 0xFF)
    }

    @Test("Negative component is clamped to 0 (no UInt32 crash)")
    func negativeComponentClamps() {
        // Explicitly pass a negative red in sRGB to verify clamp behavior.
        let color = Color(.sRGB, red: -0.5, green: 0.5, blue: 0.5)
        let hex = color.toHex()
        let r = (hex >> 16) & 0xFF
        #expect(r == 0)
    }

    @Test("Component > 1 is clamped to 0xFF (no overflow)")
    func overOneComponentClamps() {
        let color = Color(.sRGB, red: 2.0, green: 0.5, blue: 0.5)
        let hex = color.toHex()
        let r = (hex >> 16) & 0xFF
        #expect(r == 0xFF)
    }
}
