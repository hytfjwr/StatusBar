import ArgumentParser
import Foundation
import StatusBarIPC

// MARK: - PluginsCommand

struct PluginsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugins",
        abstract: "Manage plugins.yml / plugins-lock.yml",
        subcommands: [PluginsSyncCommand.self, PluginsListCommand.self]
    )
}

// MARK: - PluginsSyncCommand

struct PluginsSyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Reconcile installed plugins with plugins.yml"
    )

    @Flag(name: .long, help: "Resolve from plugins-lock.yml only; do not contact GitHub")
    var frozen: Bool = false

    func run() throws {
        let payload = try IPCClient.send(.pluginsSync(frozen: frozen))
        guard case .ok = payload else {
            throw ExitCode.failure
        }
        print("Sync started — check toasts for progress.")
    }
}

// MARK: - PluginsListCommand

struct PluginsListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List plugin manifest entries with their lock state"
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let payload = try IPCClient.send(.pluginsList)
        guard case let .pluginList(entries) = payload else {
            throw ExitCode.failure
        }

        if options.json {
            print(jsonOutput(entries))
            return
        }
        if entries.isEmpty {
            print("No plugins declared in plugins.yml")
            return
        }
        for entry in entries {
            let resolved = entry.resolvedVersion.map { "resolved=\($0)" } ?? "unresolved"
            print("\(entry.source) [declared=\(entry.declaredVersion)] [\(resolved)]")
        }
    }

    private func jsonOutput(_ entries: [PluginManifestEntryDTO]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }
}
