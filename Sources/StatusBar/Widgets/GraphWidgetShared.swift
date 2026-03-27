import SwiftUI

// MARK: - GraphDisplayMode

enum GraphDisplayMode: String, CaseIterable {
    case graphOnly
    case numericOnly
    case graphAndNumeric

    var label: String {
        switch self {
        case .graphOnly: "Graph"
        case .numericOnly: "Numeric"
        case .graphAndNumeric: "Both"
        }
    }
}

// MARK: - ThresholdEntry

struct ThresholdEntry: Equatable, Identifiable {
    let id = UUID()
    /// Fraction 0.0–1.0. Color applies when value >= this threshold.
    var above: Double
    /// Raw RGB hex (e.g. 0xFF9F0A).
    var hex: UInt32

    var color: Color {
        Color(hex: hex)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.above == rhs.above && lhs.hex == rhs.hex
    }
}

// MARK: - ThresholdEntry Serialization

extension [ThresholdEntry] {

    /// Encodes as `"60:#FF9F0A,85:#FF3B30"` for storage in ConfigValue.string.
    /// Threshold `above` is stored as a percentage integer (0–100) for YAML readability.
    func encoded() -> String {
        sorted { $0.above < $1.above }
            .map { String(format: "%d:#%06X", Int($0.above * 100), $0.hex) }
            .joined(separator: ",")
    }

    /// Decodes from the encoded string format. Invalid entries are silently dropped.
    static func decoded(from string: String) -> [ThresholdEntry] {
        guard !string.isEmpty else {
            return []
        }
        return string.split(separator: ",").compactMap { part in
            let components = part.split(separator: ":")
            guard components.count == 2,
                  let pct = Int(components[0]),
                  pct >= 0, pct <= 100,
                  components[1].hasPrefix("#"),
                  let hexVal = UInt32(components[1].dropFirst(), radix: 16)
            else {
                return nil
            }
            return ThresholdEntry(above: Double(pct) / 100.0, hex: hexVal)
        }
        .sorted { $0.above < $1.above }
    }
}

// MARK: - Threshold Color Resolution

extension [ThresholdEntry] {

    /// Returns the color for the highest threshold whose `above` <= `value`.
    /// Returns `fallback` when no threshold matches or the list is empty.
    func resolveColor(for value: Double, fallback: Color) -> Color {
        last(where: { $0.above <= value })?.color ?? fallback
    }
}

// MARK: - Numeric Animation

extension Animation {
    /// Standard animation for numeric text transitions across all widgets.
    static let numericTransition: Animation = .spring(duration: 0.35, bounce: 0.0)
}
