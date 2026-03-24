import StatusBarIPC

/// Protocol for formatting IPC results as text or JSON.
protocol OutputFormatter {
    func formatWidgetList(_ widgets: [WidgetInfoDTO]) -> String
    func formatWidgetDetail(_ widget: WidgetInfoDTO) -> String
}
