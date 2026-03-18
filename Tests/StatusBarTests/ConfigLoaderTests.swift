import Foundation
import Testing

@testable import StatusBar

@Suite("ConfigLoader — fixScientificNotation")
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
