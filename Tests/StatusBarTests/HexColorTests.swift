import Foundation
@testable import StatusBar
import Testing

struct HexColorTests {

    // MARK: - Init

    @Test("Raw value initializer stores value")
    func rawValueInit() {
        let color = HexColor(0x007AFF)
        #expect(color.rawValue == 0x007AFF)
    }

    // MARK: - Decoding

    @Test("Decodes valid hex string with # prefix")
    func decodesWithPrefix() throws {
        let json = ##""#FF6B6B""##
        let color = try JSONDecoder().decode(HexColor.self, from: Data(json.utf8))
        #expect(color.rawValue == 0xFF6B6B)
    }

    @Test("Decodes valid hex string without # prefix")
    func decodesWithoutPrefix() throws {
        let json = "\"007AFF\""
        let color = try JSONDecoder().decode(HexColor.self, from: Data(json.utf8))
        #expect(color.rawValue == 0x007AFF)
    }

    @Test("Decodes black (#000000)")
    func decodesBlack() throws {
        let json = ##""#000000""##
        let color = try JSONDecoder().decode(HexColor.self, from: Data(json.utf8))
        #expect(color.rawValue == 0x000000)
    }

    @Test("Decodes white (#FFFFFF)")
    func decodesWhite() throws {
        let json = ##""#FFFFFF""##
        let color = try JSONDecoder().decode(HexColor.self, from: Data(json.utf8))
        #expect(color.rawValue == 0xFFFFFF)
    }

    @Test("Decodes lowercase hex")
    func decodesLowercase() throws {
        let json = ##""#ff6b6b""##
        let color = try JSONDecoder().decode(HexColor.self, from: Data(json.utf8))
        #expect(color.rawValue == 0xFF6B6B)
    }

    @Test("Rejects invalid hex strings", arguments: [
        ##""#GG0000""##,
        ##""#FFF""##,
        ##""#FFFFFFF""##,
        "\"notacolor\"",
        "\"\"",
    ])
    func rejectsInvalidHex(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HexColor.self, from: Data(json.utf8))
        }
    }

    // MARK: - Encoding

    @Test("Encodes as uppercase hex with # prefix")
    func encodesWithPrefix() throws {
        let color = HexColor(0xFF6B6B)
        let data = try JSONEncoder().encode(color)
        let string = try #require(String(data: data, encoding: .utf8))
        #expect(string == ##""#FF6B6B""##)
    }

    @Test("Encodes zero-padded values correctly")
    func encodesZeroPadded() throws {
        let color = HexColor(0x000AFF)
        let data = try JSONEncoder().encode(color)
        let string = try #require(String(data: data, encoding: .utf8))
        #expect(string == ##""#000AFF""##)
    }

    // MARK: - Round-trip

    @Test("Encode → Decode round-trip preserves value", arguments: [
        UInt32(0x000000),
        UInt32(0xFFFFFF),
        UInt32(0x007AFF),
        UInt32(0xFF6B6B),
        UInt32(0x1A1A2E),
    ])
    func roundTrip(value: UInt32) throws {
        let original = HexColor(value)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HexColor.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable

    @Test("Equatable compares raw values")
    func equatable() {
        #expect(HexColor(0xFF0000) == HexColor(0xFF0000))
        #expect(HexColor(0xFF0000) != HexColor(0x00FF00))
    }
}
