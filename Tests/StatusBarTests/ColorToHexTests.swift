import AppKit
@testable import StatusBar
import SwiftUI
import Testing

/// `Color.toHex()` のクランプ挙動テスト。
///
/// P3 等の広色域で初期化された Color を sRGB に変換すると、成分が [0, 1] の範囲外
/// (負値 / 1.0 超) になることがある。クランプせずに `UInt32(x * 255)` すると
/// 負値で crash / 1.0 超でオーバーフローするため、クランプが正しく働くことを確認する。
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

    /// displayP3 で sRGB 外の純緑を作ると、sRGB 変換で負の赤成分 / 1.0 超の緑成分になる。
    /// クランプされないと `UInt32` 初期化でクラッシュするので、そのクラッシュが発生しない事を確認する。
    @Test("Wide-gamut P3 green does not crash and clamps to [0, 0xFF]")
    func p3GreenClamps() {
        let color = Color(.displayP3, red: 0, green: 1, blue: 0)
        let hex = color.toHex()
        // クランプされていれば各成分は [0, 0xFF] 範囲内。
        let r = (hex >> 16) & 0xFF
        let g = (hex >> 8) & 0xFF
        let b = hex & 0xFF
        #expect(r <= 0xFF)
        #expect(g <= 0xFF)
        #expect(b <= 0xFF)
        // 緑成分は sRGB に変換しても概ね 1.0 近傍なので 0xFF にクランプされるはず。
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
        // sRGB 空間で負の赤を明示的に指定してクランプ動作を確認する。
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
