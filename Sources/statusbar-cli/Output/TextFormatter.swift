import StatusBarIPC

/// Human-readable text output formatter.
struct TextFormatter: OutputFormatter {
    func formatWidgetList(_ widgets: [WidgetInfoDTO]) -> String {
        guard !widgets.isEmpty else {
            return "No widgets registered."
        }

        // Column headers
        let header = String(format: "%-20s %-8s %-8s %s", "ID", "SECTION", "VISIBLE", "SETTINGS")
        let separator = String(repeating: "─", count: 60)

        let rows = widgets
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { w in
                let settingsStr = w.settings.isEmpty
                    ? "–"
                    : w.settings.map { "\($0.key)=\(formatValue($0.value))" }.joined(separator: ", ")
                return String(
                    format: "%-20s %-8s %-8s %s",
                    String(w.id.prefix(20)),
                    w.position.rawValue,
                    w.isVisible ? "yes" : "no",
                    settingsStr
                )
            }

        return ([header, separator] + rows).joined(separator: "\n")
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
