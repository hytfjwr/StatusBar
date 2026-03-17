import Foundation

public enum ShellCommandError: Error {
    case timeout
}

public enum ShellCommand {
    private static let defaultEnvironment: [String: String] = ProcessInfo.processInfo.environment.merging([
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    ]) { _, new in new }

    /// Executes an external command using an argv array (no shell interpretation).
    /// This is the preferred API — immune to shell injection.
    public static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 5) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        return try await runProcess(process, timeout: timeout)
    }

    /// Executes a shell command via `/bin/bash -c`. Use the argv-based overload instead
    /// when any part of the command includes external/user-controlled data.
    public static func run(_ command: String, timeout: TimeInterval = 5) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        return try await runProcess(process, timeout: timeout)
    }

    private static func runProcess(_ process: Process, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = defaultEnvironment

            nonisolated(unsafe) var didTimeout = false
            nonisolated(unsafe) let workItem = DispatchWorkItem {
                if process.isRunning {
                    didTimeout = true
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)

            process.terminationHandler = { _ in
                workItem.cancel()
                if didTimeout {
                    continuation.resume(throwing: ShellCommandError.timeout)
                    return
                }
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            }

            do {
                try process.run()
            } catch {
                workItem.cancel()
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
