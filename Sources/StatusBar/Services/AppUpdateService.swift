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

    // GitHub repository for this app
    private static let owner = "hytfjwr"
    private static let repo = "StatusBar"
    private static let brewFormula = "hytfjwr/statusbar/statusbar"

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
            let release = try await fetchLatestRelease()
            let latestTag = release.tagName
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            let currentVersion = Self.appVersion

            recordCheck()

            guard let latest = SemanticVersion(latestTag),
                  let current = SemanticVersion(currentVersion)
            else {
                // Fallback to string comparison if parsing fails
                if latestTag != currentVersion {
                    state = .available(version: latestTag)
                } else {
                    state = .upToDate
                }
                return
            }

            if latest > current {
                state = .available(version: latestTag)
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
            appendLog("$ brew upgrade \(Self.brewFormula)")
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
    static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let isAppBundle = bundlePath.hasSuffix(".app")
        let pid = ProcessInfo.processInfo.processIdentifier

        // Only the launch command differs between .app and raw binary.
        let (launchCmd, targetPath): (String, String) = if isAppBundle {
            ("open \"$2\"", bundlePath)
        } else {
            ("\"$2\" &", ProcessInfo.processInfo.arguments[0])
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for the current process to fully exit before relaunching
        // to avoid the single-instance guard killing the new process.
        // Timeout after ~10s (50 × 0.2s) to avoid spinning forever.
        task.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done; \(launchCmd)",
            "--", "\(pid)", targetPath,
        ]

        do {
            try task.run()
        } catch {
            logger.error("Failed to spawn relaunch process: \(error.localizedDescription)")
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
        process.arguments = ["upgrade", Self.brewFormula]

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

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.networkError
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.networkError
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw UpdateError.rateLimited
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.noRelease
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

// MARK: AppUpdateService.UpdateError

extension AppUpdateService {
    enum UpdateError: LocalizedError {
        case networkError
        case rateLimited
        case noRelease

        var errorDescription: String? {
            switch self {
            case .networkError: "Network error"
            case .rateLimited: "GitHub API rate limited. Try again later."
            case .noRelease: "No releases found"
            }
        }
    }
}

// MARK: - GitHubRelease

private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
