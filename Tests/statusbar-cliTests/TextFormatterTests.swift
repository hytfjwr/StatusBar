@testable import sbar
import StatusBarIPC
import Testing

struct TextFormatterTests {
    private let formatter = TextFormatter()

    // MARK: - Helper

    private func widget(
        id: String = "test-widget",
        displayName: String = "Test Widget",
        position: WidgetPosition = .right,
        sortIndex: Int = 0,
        isVisible: Bool = true,
        settings: [String: ConfigValue] = [:]
    ) -> WidgetInfoDTO {
        WidgetInfoDTO(
            id: id,
            displayName: displayName,
            position: position,
            sortIndex: sortIndex,
            isVisible: isVisible,
            settings: settings
        )
    }

    // MARK: - formatWidgetList

    @Test("Empty list returns message")
    func emptyList() {
        let result = formatter.formatWidgetList([])
        #expect(result == "No widgets registered.")
    }

    @Test("Single widget without settings")
    func singleWidgetNoSettings() {
        let result = formatter.formatWidgetList([
            widget(id: "time", position: .right, isVisible: true),
        ])
        #expect(result.contains("time"))
        #expect(result.contains("right"))
        #expect(result.contains("yes"))
        #expect(result.contains("–"))
    }

    @Test("Widget with settings formats key=value pairs")
    func widgetWithSettings() {
        let result = formatter.formatWidgetList([
            widget(
                id: "network",
                settings: ["updateInterval": .int(2), "showIcon": .bool(true)]
            ),
        ])
        #expect(result.contains("updateInterval=2"))
        #expect(result.contains("showIcon=true"))
    }

    @Test("Widgets are sorted by sortIndex")
    func sortedBySortIndex() {
        let result = formatter.formatWidgetList([
            widget(id: "second", sortIndex: 1),
            widget(id: "first", sortIndex: 0),
            widget(id: "third", sortIndex: 2),
        ])
        let lines = result.split(separator: "\n")
        // header + separator + 3 rows
        #expect(lines.count == 5)
        #expect(lines[2].contains("first"))
        #expect(lines[3].contains("second"))
        #expect(lines[4].contains("third"))
    }

    @Test("Long widget ID is truncated to 20 characters")
    func longIdTruncated() throws {
        let longID = String(repeating: "a", count: 30)
        let result = formatter.formatWidgetList([
            widget(id: longID),
        ])
        // The ID column should not contain the full 30-char ID
        let dataRow = try #require(result.split(separator: "\n").last)
        #expect(!dataRow.contains(longID))
        #expect(dataRow.contains(String(repeating: "a", count: 20)))
    }

    @Test("All ConfigValue types format correctly in list")
    func allConfigValueTypes() {
        let result = formatter.formatWidgetList([
            widget(settings: [
                "s": .string("hello"),
                "b": .bool(false),
                "i": .int(42),
                "d": .double(3.14),
            ]),
        ])
        #expect(result.contains("s=hello"))
        #expect(result.contains("b=false"))
        #expect(result.contains("i=42"))
        #expect(result.contains("d=3.14"))
    }

    @Test("Hidden widget shows 'no' in visible column")
    func hiddenWidget() throws {
        let result = formatter.formatWidgetList([
            widget(isVisible: false),
        ])
        let dataRow = try #require(result.split(separator: "\n").last)
        #expect(dataRow.contains("no"))
    }

    // MARK: - formatWidgetDetail

    @Test("Detail shows all fields")
    func detailAllFields() {
        let result = formatter.formatWidgetDetail(
            widget(
                id: "battery",
                displayName: "Battery",
                position: .right,
                sortIndex: 5,
                isVisible: true
            )
        )
        #expect(result.contains("ID:       battery"))
        #expect(result.contains("Name:     Battery"))
        #expect(result.contains("Section:  right"))
        #expect(result.contains("Visible:  yes"))
        #expect(result.contains("Index:    5"))
    }

    @Test("Detail with settings lists them sorted by key")
    func detailWithSettings() throws {
        let result = formatter.formatWidgetDetail(
            widget(settings: [
                "z-key": .string("last"),
                "a-key": .int(1),
            ])
        )
        #expect(result.contains("Settings:"))
        let lines = result.split(separator: "\n")
        let settingsLines = lines.filter { $0.hasPrefix("  ") }
        #expect(settingsLines.count == 2)
        // a-key should come before z-key
        let firstSettingIndex = try #require(lines.firstIndex { $0.contains("a-key") })
        let secondSettingIndex = try #require(lines.firstIndex { $0.contains("z-key") })
        #expect(firstSettingIndex < secondSettingIndex)
    }

    @Test("Detail without settings omits Settings section")
    func detailNoSettings() {
        let result = formatter.formatWidgetDetail(widget())
        #expect(!result.contains("Settings:"))
    }
}
