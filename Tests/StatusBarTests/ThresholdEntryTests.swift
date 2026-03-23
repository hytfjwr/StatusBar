import Foundation
@testable import StatusBar
import SwiftUI
import Testing

struct ThresholdEntryTests {

    // MARK: - Serialization

    @Test("Empty array encodes to empty string")
    func encodeEmpty() {
        let entries: [ThresholdEntry] = []
        #expect(entries.encoded() == "")
    }

    @Test("Single entry encodes correctly")
    func encodeSingle() {
        let entries = [ThresholdEntry(above: 0.60, hex: 0xFF9F0A)]
        #expect(entries.encoded() == "60:#FF9F0A")
    }

    @Test("Multiple entries encode sorted ascending")
    func encodeMultiple() {
        let entries = [
            ThresholdEntry(above: 0.85, hex: 0xFF3B30),
            ThresholdEntry(above: 0.60, hex: 0xFF9F0A),
        ]
        #expect(entries.encoded() == "60:#FF9F0A,85:#FF3B30")
    }

    @Test("Empty string decodes to empty array")
    func decodeEmpty() {
        let result = [ThresholdEntry].decoded(from: "")
        #expect(result.isEmpty)
    }

    @Test("Single entry decodes correctly")
    func decodeSingle() {
        let result = [ThresholdEntry].decoded(from: "60:#FF9F0A")
        #expect(result.count == 1)
        #expect(result[0].above == 0.60)
        #expect(result[0].hex == 0xFF9F0A)
    }

    @Test("Multiple entries decode sorted")
    func decodeMultiple() {
        let result = [ThresholdEntry].decoded(from: "85:#FF3B30,60:#FF9F0A")
        #expect(result.count == 2)
        #expect(result[0].above == 0.60)
        #expect(result[1].above == 0.85)
    }

    @Test("Malformed entries are silently dropped")
    func decodeMalformed() {
        let result = [ThresholdEntry].decoded(from: "60:#FF9F0A,invalid,85:#FF3B30")
        #expect(result.count == 2)
    }

    @Test("Round-trip preserves data")
    func roundTrip() {
        let original = [
            ThresholdEntry(above: 0.50, hex: 0x34C759),
            ThresholdEntry(above: 0.75, hex: 0xFF9F0A),
            ThresholdEntry(above: 0.90, hex: 0xFF3B30),
        ]
        let decoded = [ThresholdEntry].decoded(from: original.encoded())
        #expect(decoded == original)
    }

    @Test("Out of range percentage is dropped")
    func outOfRange() {
        let result = [ThresholdEntry].decoded(from: "150:#FF0000,-10:#00FF00,50:#0000FF")
        #expect(result.count == 1)
        #expect(result[0].above == 0.50)
    }

    // MARK: - Color Resolution

    @Test("Empty thresholds return fallback")
    func resolveEmpty() {
        let thresholds: [ThresholdEntry] = []
        let color = thresholds.resolveColor(for: 0.95, fallback: .blue)
        #expect(color == .blue)
    }

    @Test("Value below all thresholds returns fallback")
    func resolveBelowAll() {
        let thresholds = [
            ThresholdEntry(above: 0.60, hex: 0xFF9F0A),
            ThresholdEntry(above: 0.85, hex: 0xFF3B30),
        ]
        let color = thresholds.resolveColor(for: 0.30, fallback: .blue)
        #expect(color == .blue)
    }

    @Test("Value matching exactly returns that threshold color")
    func resolveExactMatch() {
        let thresholds = [
            ThresholdEntry(above: 0.60, hex: 0xFF9F0A),
            ThresholdEntry(above: 0.85, hex: 0xFF3B30),
        ]
        let color = thresholds.resolveColor(for: 0.60, fallback: .blue)
        #expect(color == Color(hex: 0xFF9F0A))
    }

    @Test("Value above highest threshold returns highest threshold color")
    func resolveAboveAll() {
        let thresholds = [
            ThresholdEntry(above: 0.60, hex: 0xFF9F0A),
            ThresholdEntry(above: 0.85, hex: 0xFF3B30),
        ]
        let color = thresholds.resolveColor(for: 0.95, fallback: .blue)
        #expect(color == Color(hex: 0xFF3B30))
    }

    @Test("Value between thresholds returns the lower matching threshold")
    func resolveBetween() {
        let thresholds = [
            ThresholdEntry(above: 0.60, hex: 0xFF9F0A),
            ThresholdEntry(above: 0.85, hex: 0xFF3B30),
        ]
        let color = thresholds.resolveColor(for: 0.70, fallback: .blue)
        #expect(color == Color(hex: 0xFF9F0A))
    }
}
