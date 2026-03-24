import ArgumentParser
import StatusBarIPC

// MARK: - SetCommand

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set widget or global settings",
        discussion: """
        Widget setting:  sbar set <widget> <key>=<value>
        Global setting:  sbar set --global <key.path>=<value>

        Examples:
          sbar set battery showPercentage=true
          sbar set cpu-graph visible=false
          sbar set --global bar.height=44
          sbar set --global appearance.accent=#FF0000
        """
    )

    @Flag(name: .long, help: "Set a global preference instead of a widget setting")
    var global: Bool = false

    @Argument(help: "Widget ID (omit with --global) and key=value assignment")
    var args: [String]

    func run() throws {
        if global {
            try handleGlobal()
        } else {
            try handleWidget()
        }
    }

    private func handleGlobal() throws {
        guard args.count == 1 else {
            throw ValidationError("Expected: sbar set --global <key.path>=<value>")
        }
        let (key, rawValue) = try parseAssignment(args[0])
        let value = parseConfigValue(rawValue)
        let payload = try IPCClient.send(.setGlobal(keyPath: key, value: value))
        guard case .ok = payload else {
            throw ExitCode.failure
        }
        print("OK")
    }

    private func handleWidget() throws {
        guard args.count == 2 else {
            throw ValidationError("Expected: sbar set <widget> <key>=<value>")
        }
        let widgetID = args[0]
        let (key, rawValue) = try parseAssignment(args[1])
        let value = parseConfigValue(rawValue)
        let payload = try IPCClient.send(.setWidget(id: widgetID, key: key, value: value))
        guard case .ok = payload else {
            throw ExitCode.failure
        }
        print("OK")
    }
}

// MARK: - Parsing helpers

private func parseAssignment(_ string: String) throws -> (key: String, value: String) {
    guard let eqIndex = string.firstIndex(of: "=") else {
        throw ValidationError("Invalid assignment '\(string)'. Expected key=value format.")
    }
    let key = String(string[..<eqIndex])
    let value = String(string[string.index(after: eqIndex)...])
    guard !key.isEmpty else {
        throw ValidationError("Key cannot be empty in '\(string)'")
    }
    return (key, value)
}

/// Parse a string value into the most specific ConfigValue type.
/// Priority: Bool → Int → Double → String (matches ConfigValue's Codable decode order).
func parseConfigValue(_ string: String) -> ConfigValue {
    // Bool
    if string.lowercased() == "true" {
        return .bool(true)
    }
    if string.lowercased() == "false" {
        return .bool(false)
    }
    // Int
    if let v = Int(string) {
        return .int(v)
    }
    // Double
    if let v = Double(string) {
        return .double(v)
    }
    // String
    return .string(string)
}
