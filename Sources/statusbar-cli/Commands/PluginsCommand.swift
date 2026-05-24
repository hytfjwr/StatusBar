import ArgumentParser
import Foundation
import StatusBarIPC

// MARK: - PluginsCommand

struct PluginsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugins",
        abstract: "Manage plugins.yml / plugins-lock.yml",
        subcommands: [
            PluginsSyncCommand.self,
            PluginsListCommand.self,
            PluginsInstallCommand.self,
            PluginsUninstallCommand.self,
        ]
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

// MARK: - PluginsInstallCommand

struct PluginsInstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a plugin from GitHub, updating plugins.yml + plugins-lock.yml"
    )

    @Argument(help: ArgumentHelp(
        "Plugin source — accepts owner/repo, github:owner/repo, or https://github.com/owner/repo",
        valueName: "source"
    ))
    var source: String

    @Option(name: .long, help: "Release tag to install (defaults to the latest GitHub release)")
    var version: String?

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let normalizedSource: String
        do {
            normalizedSource = try PluginSourceParser.normalize(source)
        } catch {
            throw ValidationError(error.localizedDescription)
        }

        let payload = try IPCClient.send(.pluginsInstall(source: normalizedSource, version: version))
        guard case let .pluginInstalled(installed) = payload else {
            throw ExitCode.failure
        }

        if options.json {
            print(jsonOutput(installed))
            return
        }
        print("Installed \(installed.name) v\(installed.version) (\(installed.source))")
    }

    private func jsonOutput(_ dto: InstalledPluginDTO) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(dto),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}

// MARK: - PluginsUninstallCommand

struct PluginsUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove a plugin from plugins.yml + plugins-lock.yml and delete its bundle"
    )

    @Argument(help: ArgumentHelp(
        "Plugin source — accepts owner/repo, github:owner/repo, or https://github.com/owner/repo",
        valueName: "source"
    ))
    var source: String

    func run() throws {
        let normalizedSource: String
        do {
            normalizedSource = try PluginSourceParser.normalize(source)
        } catch {
            throw ValidationError(error.localizedDescription)
        }

        let payload = try IPCClient.send(.pluginsUninstall(source: normalizedSource))
        guard case .ok = payload else {
            throw ExitCode.failure
        }
        print("Uninstalled \(normalizedSource)")
    }
}

// MARK: - PluginSourceParser

/// Normalizes the three accepted source forms (owner/repo, github:owner/repo,
/// https://github.com/owner/repo) into the canonical `github:owner/repo` string
/// stored in plugins.yml.
enum PluginSourceParser {
    enum ParseError: Error, LocalizedError {
        case empty
        case invalidFormat(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                "source must not be empty"
            case let .invalidFormat(input):
                "invalid source '\(input)' — expected owner/repo, github:owner/repo, or https://github.com/owner/repo"
            }
        }
    }

    static func normalize(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.empty
        }

        let stripped: String = if trimmed.hasPrefix("github:") {
            String(trimmed.dropFirst("github:".count))
        } else if let owner = stripGitHubURL(trimmed) {
            owner
        } else {
            trimmed
        }

        let parts = stripped.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              validateSegment(parts[0])
        else {
            throw ParseError.invalidFormat(input)
        }
        // Strip a trailing ".git" from the repo segment so pasted clone URLs (e.g.
        // `git@`/`https` clone form ending in `.git`) canonicalize to the same source string
        // that GitHubPluginInstaller.parseGitHubURL stores on the registry record. Without
        // this, plugins.yml carries `github:owner/repo.git` while the registry sees
        // `github:owner/repo`, and sync()'s drift check uninstalls + reinstalls every run.
        var repo = parts[1]
        if repo.hasSuffix(".git") {
            repo = repo.dropLast(4)
        }
        guard validateSegment(repo) else {
            throw ParseError.invalidFormat(input)
        }
        return "github:\(parts[0])/\(repo)"
    }

    /// Returns `owner/repo` for an https://github.com/ URL, otherwise nil.
    private static func stripGitHubURL(_ input: String) -> String? {
        let prefixes = ["https://github.com/", "http://github.com/"]
        for prefix in prefixes where input.hasPrefix(prefix) {
            let rest = input.dropFirst(prefix.count)
            // Drop trailing slash and anything after a second slash (e.g. /tree/main).
            let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count >= 2 else {
                return nil
            }
            return "\(parts[0])/\(parts[1])"
        }
        return nil
    }

    /// Mirrors PluginsManifestEntry.validateOwnerRepo in the app: start alphanumeric,
    /// then `[A-Za-z0-9._-]`.
    private static func validateSegment(_ s: Substring) -> Bool {
        let pattern = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/
        return s.wholeMatch(of: pattern) != nil
    }
}
