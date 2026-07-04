@testable import StatusBar
import Testing

// MARK: - CustomScriptWidgetOutputTests

struct CustomScriptWidgetOutputTests {
    @Test("Plain text stdout becomes the text as-is")
    func plainTextBecomesText() {
        let output = CustomScriptWidget.parseOutput("main")
        #expect(output == CustomWidgetOutput(text: "main"))
    }

    @Test("Only the first line of multi-line output is used")
    func multiLineUsesFirstLineOnly() {
        let output = CustomScriptWidget.parseOutput("main\nextra ignored line")
        #expect(output.text == "main")
    }

    @Test("Empty stdout produces empty text")
    func emptyStdoutProducesEmptyText() {
        let output = CustomScriptWidget.parseOutput("")
        #expect(output.text.isEmpty)
    }

    @Test("Complete JSON populates all fields, color hex is converted")
    func completeJSONPopulatesAllFields() {
        let stdout = ##"{"text": "3 pods", "icon": "⎈", "sfSymbol": "circle.fill", "color": "#FF3B30"}"##
        let output = CustomScriptWidget.parseOutput(stdout)

        #expect(output.text == "3 pods")
        #expect(output.icon == "⎈")
        #expect(output.sfSymbol == "circle.fill")
        #expect(output.colorHex == 0xFF3B30)
    }

    @Test("Partial JSON (text only) leaves other fields nil")
    func partialJSONLeavesOthersNil() {
        let stdout = #"{"text": "just text"}"#
        let output = CustomScriptWidget.parseOutput(stdout)

        #expect(output.text == "just text")
        #expect(output.icon == nil)
        #expect(output.sfSymbol == nil)
        #expect(output.colorHex == nil)
    }

    @Test("Malformed JSON (starts with '{' but invalid) falls back to plain text")
    func malformedJSONFallsBackToPlainText() {
        let stdout = "{not valid json"
        let output = CustomScriptWidget.parseOutput(stdout)
        #expect(output.text == stdout)
        #expect(output.icon == nil)
        #expect(output.sfSymbol == nil)
        #expect(output.colorHex == nil)
    }
}
