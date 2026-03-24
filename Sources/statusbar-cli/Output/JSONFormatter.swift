import Foundation
import StatusBarIPC

/// JSON output formatter for machine consumption.
struct JSONFormatter: OutputFormatter {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    func formatWidgetList(_ widgets: [WidgetInfoDTO]) -> String {
        (try? String(data: encoder.encode(widgets), encoding: .utf8)) ?? "[]"
    }

    func formatWidgetDetail(_ widget: WidgetInfoDTO) -> String {
        (try? String(data: encoder.encode(widget), encoding: .utf8)) ?? "{}"
    }
}
