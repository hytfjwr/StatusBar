import AppKit
import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "AppUpdateService")

// MARK: - AppUpdateService

@MainActor
@Observable
final class AppUpdateService {
    static let shared = AppUpdateService()

    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case error(String)
    }

    enum UpdatePhase: Equatable {
        case preparing
        case updating
        case complete
        case failed(String)

        var label: String {
            switch self {
            case .preparing: "Preparing…"
            case .updating: "Updating via Homebrew…"
            case .complete: "Update complete!"
            case let .failed(message): "Failed: \(message)"
            }
        }
    }

    private(set) var state: UpdateState = .idle

    /// Last time we checked (persisted across launches for auto-check throttling).
    private(set) var lastCheckDate: Date?

    // Update execution state
    private(set) var updatePhase: UpdatePhase?
    private(set) var updateLog: String = ""
    private(set) var updateProgress: Double = 0
    private var updateProcess: Process?

    nonisolated private static let brewCask = "statusbar"

    /// Minimum interval between automatic checks (1 hour).
    private static let autoCheckInterval: TimeInterval = 3_600

    private init() {
        let ts = UserDefaults.standard.double(forKey: "appUpdate.lastCheckTimestamp")
        if ts > 0 {
            lastCheckDate = Date(timeIntervalSince1970: ts)
        }
    }

    // MARK: - Public API

    /// Check for updates. Called manually from UI or automatically on launch.
    func checkForUpdates() async {
        state = .checking

        do {
            let latestVersion = try await fetchBrewLatestVersion()
            let currentVersion = Self.appVersion

            recordCheck()

            guard let latest = SemanticVersion(latestVersion),
                  let current = SemanticVersion(currentVersion)
            else {
                if latestVersion != currentVersion {
                    state = .available(version: latestVersion)
                } else {
                    state = .upToDate
                }
                return
            }

            if latest > current {
                state = .available(version: latestVersion)
            } else {
                state = .upToDate
            }
        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// Auto-check on launch if enough time has passed.
    func checkIfNeeded() async {
        if let last = lastCheckDate,
           Date().timeIntervalSince(last) < Self.autoCheckInterval
        {
            return
        }
        await checkForUpdates()
    }

    // MARK: - Update Execution

    /// Perform the actual update via Homebrew.
    func performUpdate() async {
        updatePhase = .preparing
        updateLog = ""
        updateProgress = 0.1

        guard let brewPath = Self.findBrewPath() else {
            appendLog("Error: Homebrew not found.")
            appendLog("Install from https://brew.sh or verify your installation.")
            updatePhase = .failed("Homebrew not found")
            return
        }

        appendLog("Found Homebrew at \(brewPath)")

        updatePhase = .updating
        updateProgress = 0.2

        do {
            appendLog("$ brew upgrade --cask \(Self.brewCask)")
            let exitCode = try await runBrewUpgrade(brewPath: brewPath)

            // Check if cancelled while awaiting
            guard updatePhase != nil else {
                return
            }

            if exitCode == 0 {
                updateProgress = 1.0
                appendLog("Update complete!")
                updatePhase = .complete
            } else {
                appendLog("brew exited with code \(exitCode)")
                updatePhase = .failed("brew exited with code \(exitCode)")
            }
        } catch {
            guard updatePhase != nil else {
                return
            }
            appendLog("Error: \(error.localizedDescription)")
            updatePhase = .failed(error.localizedDescription)
        }
    }

    /// Cancel the running update process.
    func cancelUpdate() {
        updateProcess?.terminate()
        updateProcess = nil
        updatePhase = nil
    }

    /// Reset update state for a fresh attempt.
    func resetUpdateState() {
        updatePhase = nil
        updateLog = ""
        updateProgress = 0
    }

    /// Relaunch the app after an update.
    ///
    /// Uses `posix_spawn` with `POSIX_SPAWN_SETSID` to place the relaunch
    /// helper shell in a brand-new session, fully detached from this process.
    /// A plain `Process()` (NSTask) leaves the child in the same process group,
    /// which can cause it to be killed when the parent terminates.
    static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let isAppBundle = bundlePath.hasSuffix(".app")
        let pid = ProcessInfo.processInfo.processIdentifier

        let targetPath = isAppBundle ? bundlePath : ProcessInfo.processInfo.arguments[0]
        let launchCmd = if isAppBundle {
            // Prefer /Applications symlink which survives `brew upgrade` path changes.
            // Fall back to the original path ($2) for non-Homebrew installs.
            #"if [ -e "/Applications/StatusBar.app" ]; then open "/Applications/StatusBar.app"; else open "$2"; fi"#
        } else {
            #""$2" &"#
        }

        // The shell script waits for the current process to fully exit before
        // relaunching to avoid the single-instance guard killing the new process.
        // Timeout after ~10s (50 × 0.2s) to avoid spinning forever.
        // Diagnostic output goes to /tmp/statusbar-relaunch.log.
        let logFile = "/tmp/statusbar-relaunch.log"
        let script = """
        exec > "\(logFile)" 2>&1
        echo "relaunch: started at $(date), waiting for PID $1"
        i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done
        echo "relaunch: PID $1 exited after ${i} polls"
        \(launchCmd)
        echo "relaunch: launch exit code $? at $(date)"
        """

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        // POSIX_SPAWN_SETSID: create the child in a new session so it is
        // completely independent of the parent's process group.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let argv: [String?] = ["/bin/sh", "-c", script, "--", "\(pid)", targetPath, nil]
        var cArgv = argv.map { $0.flatMap { strdup($0) } }

        var childPid: pid_t = 0
        let spawnResult = posix_spawn(
            &childPid, "/bin/sh", nil, &attr,
            &cArgv, environ
        )

        cArgv.compactMap(\.self).forEach { free($0) }
        posix_spawnattr_destroy(&attr)

        if spawnResult != 0 {
            logger.error("posix_spawn failed with code \(spawnResult)")
        } else {
            logger.info("Spawned relaunch helper (child PID \(childPid))")
        }

        // Close regular NSWindows (Preferences, Update, Onboarding) before
        // terminating. NSPanel subclasses (BarWindow, PopupPanel) are left alone.
        // Without this, NSApp.terminate can stall on SwiftUI hosting-view teardown
        // inside titled windows, preventing the app from actually exiting.
        for window in NSApp.windows where !(window is NSPanel) {
            window.close()
        }

        NSApp.terminate(nil)
    }

    // MARK: - Version

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Private

    private func appendLog(_ text: String) {
        updateLog += text + "\n"
    }

    private func recordCheck() {
        let now = Date()
        lastCheckDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "appUpdate.lastCheckTimestamp")
    }

    private static func findBrewPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew", // Apple Silicon
            "/usr/local/bin/brew", // Intel
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func runBrewUpgrade(brewPath: String) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["upgrade", "--cask", Self.brewCask]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let fileHandle = pipe.fileHandleForReading

        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.updateLog += output
                    if let self, updateProgress < 0.9 {
                        updateProgress = min(updateProgress + 0.02, 0.9)
                    }
                }
            }
        }

        updateProcess = process
        try process.run()

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }

        updateProcess = nil
        return status
    }

    nonisolated private func fetchBrewLatestVersion() async throws -> String {
        let output = try await ShellCommand.run(
            "brew", arguments: ["info", "--json=v2", "--cask", Self.brewCask], timeout: 10
        )
        let data = Data(output.utf8)
        let json = try JSONDecoder().decode(BrewInfoResponse.self, from: data)

        guard let cask = json.casks.first else {
            throw UpdateError.caskNotFound
        }

        return cask.version
    }
}

// MARK: AppUpdateService.UpdateError

extension AppUpdateService {
    enum UpdateError: LocalizedError {
        case caskNotFound

        var errorDescription: String? {
            switch self {
            case .caskNotFound: "Homebrew cask not found"
            }
        }
    }
}

// MARK: - BrewInfoResponse

private struct BrewInfoResponse: Decodable {
    struct Cask: Decodable {
        let version: String
    }

    let casks: [Cask]
}
