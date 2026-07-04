import Combine
import OSLog
import StatusBarKit
import SwiftUI

private let logger = Logger(subsystem: "com.statusbar", category: "CustomScriptWidget")

// MARK: - CustomWidgetOutput

/// Parsed result of a custom widget script's stdout.
struct CustomWidgetOutput: Equatable {
    var text: String
    var icon: String?
    var sfSymbol: String?
    var colorHex: UInt32?
}

// MARK: - CustomScriptWidget

@MainActor
@Observable
final class CustomScriptWidget: StatusBarWidget {
    let config: CustomWidgetConfig

    var id: String {
        config.widgetID
    }

    var position: WidgetPosition {
        config.position
    }

    var updateInterval: TimeInterval? {
        config.timerInterval
    }

    var sfSymbolName: String {
        "terminal"
    }

    private var output: CustomWidgetOutput?
    private var timer: AnyCancellable?
    private var isRunning = false
    private var scriptInFlight = false

    init(config: CustomWidgetConfig) {
        self.config = config
    }

    func start() {
        timer?.cancel()
        isRunning = true
        runScript()
        guard let interval = config.timerInterval else {
            return
        }
        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.runScript()
            }
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    private func runScript() {
        guard isRunning, !scriptInFlight else {
            return
        }
        scriptInFlight = true
        let script = config.script
        let timeout = config.clampedTimeout
        Task {
            let result = try? await ShellCommand.runWithResult(script, timeout: timeout)
            self.scriptInFlight = false
            guard let result, result.exitCode == 0 else {
                let prefix = script.prefix(40)
                let detail = result.map { "exit \($0.exitCode): \($0.stderr)" } ?? "execution failed"
                logger.warning("customWidgets '\(self.config.id)' script '\(prefix)' failed: \(detail)")
                return
            }
            withAnimation(.numericTransition) {
                self.output = Self.parseOutput(result.stdout)
            }
        }
    }

    private func handleTap() {
        guard let clickScript = config.clickScript else {
            runScript()
            return
        }
        let timeout = config.clampedTimeout
        Task {
            _ = try? await ShellCommand.runWithResult(clickScript, timeout: timeout)
            self.runScript()
        }
    }

    // MARK: - Output Parsing

    private struct JSONOutput: Decodable {
        var text: String?
        var icon: String?
        var sfSymbol: String?
        var color: HexColor?
    }

    /// Parses a script's stdout into a `CustomWidgetOutput`. Pure function for testability.
    nonisolated static func parseOutput(_ stdout: String) -> CustomWidgetOutput {
        if stdout.hasPrefix("{"),
           let data = stdout.data(using: .utf8),
           let json = try? JSONDecoder().decode(JSONOutput.self, from: data)
        {
            return CustomWidgetOutput(
                text: json.text ?? "",
                icon: json.icon,
                sfSymbol: json.sfSymbol,
                colorHex: json.color?.rawValue
            )
        }
        let firstLine = stdout.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return CustomWidgetOutput(text: firstLine)
    }

    func body() -> some View {
        HStack(spacing: 4) {
            if let icon = output?.icon {
                Text(icon)
                    .font(Theme.labelFont)
            } else if let sfSymbol = output?.sfSymbol {
                Image(systemName: sfSymbol)
                    .font(Theme.sfIconFont)
            } else if let icon = config.icon {
                Text(icon)
                    .font(Theme.labelFont)
            } else if let sfSymbol = config.sfSymbol {
                Image(systemName: sfSymbol)
                    .font(Theme.sfIconFont)
            } else if output == nil {
                Image(systemName: "terminal")
                    .font(Theme.sfIconFont)
                    .foregroundStyle(.tertiary)
            }

            if let text = output?.text, !text.isEmpty {
                Text(text)
                    .font(Theme.labelFont)
                    .foregroundStyle(output?.colorHex.map { Color(hex: $0) } ?? .primary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { [weak self] in
            self?.handleTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(config.id)
        .accessibilityValue(output?.text ?? "")
    }
}
