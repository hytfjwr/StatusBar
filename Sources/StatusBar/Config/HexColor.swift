import Foundation

/// A color value that encodes/decodes as a `"#RRGGBB"` string in YAML,
/// while storing a `UInt32` internally for compatibility with the rest of the app.
struct HexColor: Codable, Equatable {
    let rawValue: UInt32

    init(_ value: UInt32) {
        rawValue = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let hex = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected hex color like \"#007AFF\", got \"\(string)\""
            )
        }
        rawValue = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "#%06X", rawValue))
    }
}
