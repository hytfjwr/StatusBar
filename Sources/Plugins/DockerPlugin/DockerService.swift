import OSLog
import StatusBarKit
import SwiftUI

private let logger = Logger(subsystem: "com.statusbar", category: "DockerService")

final class DockerService: @unchecked Sendable {
    struct Container {
        let name: String
        let state: String
        let composeProject: String?

        @MainActor var stateColor: Color {
            switch state {
            case "running": Theme.green
            case "paused": Theme.yellow
            case "dead",
                "exited": Theme.red
            default: Color.white.opacity(0.5)
            }
        }
    }

    struct ContainerGroup {
        let project: String
        let containers: [Container]

        var runningCount: Int {
            containers.count(where: { $0.state == "running" })
        }

        var allRunning: Bool {
            containers.allSatisfy { $0.state == "running" }
        }

        var allStopped: Bool {
            containers.allSatisfy { $0.state != "running" }
        }
    }

    struct Result {
        let available: Bool
        let containers: [Container]

        /// Containers grouped by compose project. Standalone containers are excluded.
        var groups: [ContainerGroup] {
            let grouped = Dictionary(grouping: containers.filter { $0.composeProject != nil }) {
                $0.composeProject!
            }
            return grouped.map { ContainerGroup(project: $0.key, containers: $0.value) }
                .sorted { $0.project < $1.project }
        }

        /// Containers not part of any compose project.
        var standaloneContainers: [Container] {
            containers.filter { $0.composeProject == nil }
        }
    }

    func fetchContainers() async -> Result {
        do {
            let output = try await ShellCommand.run(
                "docker",
                arguments: [
                    "ps", "-a", "--format",
                    "{{.Names}}\t{{.State}}\t{{.Label \"com.docker.compose.project\"}}",
                ]
            )
            guard !output.isEmpty else {
                return Result(available: true, containers: [])
            }

            let containers = output.split(separator: "\n").compactMap { line -> Container? in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2 else {
                    return nil
                }
                let project = parts.count >= 3 && !parts[2].isEmpty ? String(parts[2]) : nil
                return Container(name: String(parts[0]), state: String(parts[1]), composeProject: project)
            }

            return Result(available: true, containers: containers)
        } catch {
            logger.debug("fetchContainers failed: \(error.localizedDescription)")
            return Result(available: false, containers: [])
        }
    }

    func startProject(_ project: String) async {
        do {
            _ = try await ShellCommand.run(
                "docker", arguments: ["compose", "-p", project, "start"],
                timeout: 30
            )
        } catch {
            logger.debug("startProject \(project) failed: \(error.localizedDescription)")
        }
    }

    func stopProject(_ project: String) async {
        do {
            _ = try await ShellCommand.run(
                "docker", arguments: ["compose", "-p", project, "stop"],
                timeout: 30
            )
        } catch {
            logger.debug("stopProject \(project) failed: \(error.localizedDescription)")
        }
    }
}
