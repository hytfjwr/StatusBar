import StatusBarIPC

/// Human-readable text output formatter.
struct TextFormatter: OutputFormatter {
    func formatWidgetList(_ widgets: [WidgetInfoDTO]) -> String {
        guard !widgets.isEmpty else {
            return "No widgets registered."
        }

        let rows = widgets
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { w in
                let settingsStr = w.settings.isEmpty
                    ? "–"
                    : w.settings.map { "\($0.key)=\(formatValue($0.value))" }.joined(separator: ", ")
                return formatRow(String(w.id.prefix(20)), w.position.rawValue, w.isVisible ? "yes" : "no", settingsStr)
            }

        let header = formatRow("ID", "SECTION", "VISIBLE", "SETTINGS")
        let separator = String(repeating: "─", count: 60)
        return ([header, separator] + rows).joined(separator: "\n")
    }

    private func formatRow(_ id: String, _ section: String, _ visible: String, _ settings: String) -> String {
        let cols = [
            id.padding(toLength: 20, withPad: " ", startingAt: 0),
            section.padding(toLength: 8, withPad: " ", startingAt: 0),
            visible.padding(toLength: 8, withPad: " ", startingAt: 0),
            settings,
        ]
        return cols.joined(separator: " ")
    }

    func formatWidgetDetail(_ widget: WidgetInfoDTO) -> String {
        var lines = [
            "ID:       \(widget.id)",
            "Name:     \(widget.displayName)",
            "Section:  \(widget.position.rawValue)",
            "Visible:  \(widget.isVisible ? "yes" : "no")",
            "Index:    \(widget.sortIndex)",
        ]

        if !widget.settings.isEmpty {
            lines.append("Settings:")
            for (key, value) in widget.settings.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key) = \(formatValue(value))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatValue(_ value: ConfigValue) -> String {
        switch value {
        case let .string(v): v
        case let .bool(v): v ? "true" : "false"
        case let .int(v): "\(v)"
        case let .double(v): "\(v)"
        @unknown default: "\(value)"
        }
    }
}
