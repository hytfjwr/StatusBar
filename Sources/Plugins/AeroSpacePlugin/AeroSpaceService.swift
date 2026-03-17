import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "AeroSpaceService")

final class AeroSpaceService: @unchecked Sendable {
    struct WorkspaceData {
        let id: String
        let apps: [String]
        let monitorID: Int?
    }

    struct Result {
        let focused: String
        let workspaces: [WorkspaceData]
    }

    /// File path used for event-driven workspace change detection.
    /// Configure AeroSpace with: exec-on-workspace-change = ['/bin/bash', '-c',
    /// 'echo "$AEROSPACE_FOCUSED_WORKSPACE" > "$TMPDIR/statusbar_focused_workspace"']
    static let focusedWorkspaceFile: String = {
        let tmpDir = FileManager.default.temporaryDirectory.path
        return "\(tmpDir)/statusbar_focused_workspace"
    }()

    func fetchWorkspaces() async -> Result {
        do {
            // 2 CLI calls: focused workspace + all windows with monitor IDs
            async let focusedTask = ShellCommand.run("aerospace", arguments: ["list-workspaces", "--focused"])
            async let windowsTask = ShellCommand
                .run(
                    "aerospace",
                    arguments: [
                        "list-windows", "--all", "--json",
                        "--format", "%{workspace}%{app-name}%{monitor-appkit-nsscreen-screens-id}",
                    ]
                )

            let focused = try await focusedTask.trimmingCharacters(in: .whitespacesAndNewlines)
            let windowsJSON = try await windowsTask

            // Parse windows JSON to derive workspace list, app mappings, and monitor IDs
            var appsByWorkspace: [String: [String]] = [:]
            var monitorByWorkspace: [String: Int] = [:]
            if let data = windowsJSON.data(using: .utf8),
               let windows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            {
                for window in windows {
                    guard let ws = window["workspace"] as? String else { continue }
                    if let app = window["app-name"] as? String,
                       !appsByWorkspace[ws, default: []].contains(app)
                    {
                        appsByWorkspace[ws, default: []].append(app)
                    }
                    if let monitor = window["monitor-appkit-nsscreen-screens-id"] as? Int {
                        monitorByWorkspace[ws] = monitor
                    }
                }
            }

            // Ensure focused workspace is always included
            var allWorkspaceIDs = Set(appsByWorkspace.keys)
            if !focused.isEmpty {
                allWorkspaceIDs.insert(focused)
            }

            // Sort: numeric first (1-9), then alpha (A-Z)
            let sorted = allWorkspaceIDs.sorted { a, b in
                let aNum = Int(a)
                let bNum = Int(b)
                if let an = aNum, let bn = bNum {
                    return an < bn
                }
                if aNum != nil {
                    return true
                }
                if bNum != nil {
                    return false
                }
                return a < b
            }

            let workspaces = sorted.map { ws in
                WorkspaceData(id: ws, apps: appsByWorkspace[ws] ?? [], monitorID: monitorByWorkspace[ws])
            }

            return Result(focused: focused, workspaces: workspaces)
        } catch {
            logger.debug("fetchWorkspaces failed: \(error.localizedDescription)")
            return Result(focused: "", workspaces: [])
        }
    }
}
