@testable import sbar
import Testing

struct ParseConfigValueTests {
    @Test
    func parsesBool() {
        #expect(parseConfigValue("true") == .bool(true))
        #expect(parseConfigValue("false") == .bool(false))
        #expect(parseConfigValue("TRUE") == .bool(true))
        #expect(parseConfigValue("False") == .bool(false))
    }

    @Test
    func parsesInt() {
        #expect(parseConfigValue("42") == .int(42))
        #expect(parseConfigValue("0") == .int(0))
        #expect(parseConfigValue("-10") == .int(-10))
    }

    @Test
    func parsesDouble() {
        #expect(parseConfigValue("3.14") == .double(3.14))
        #expect(parseConfigValue("0.5") == .double(0.5))
        #expect(parseConfigValue("-1.5") == .double(-1.5))
    }

    @Test
    func parsesString() {
        #expect(parseConfigValue("hello") == .string("hello"))
        #expect(parseConfigValue("#FF0000") == .string("#FF0000"))
        #expect(parseConfigValue("HH:mm:ss") == .string("HH:mm:ss"))
    }

    @Test("Integer-like string is parsed as Int, not Double")
    func intNotDouble() {
        #expect(parseConfigValue("44") == .int(44))
    }
}
