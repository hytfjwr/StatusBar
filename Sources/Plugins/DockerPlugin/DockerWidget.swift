import Combine
import StatusBarKit
import SwiftUI

// MARK: - DockerWidget

@MainActor
@Observable
public final class DockerWidget: StatusBarWidget {
    public let id = "docker"
    public let position: WidgetPosition = .right
    public let updateInterval: TimeInterval? = 10
    public var sfSymbolName: String { "shippingbox" }

    private var timer: AnyCancellable?
    private let service = DockerService()
    private var popupPanel: PopupPanel?
    private var containers: [DockerService.Container] = []
    private var transitioningContainers: [String: String] = [:]
    private var transitioningProjects: [String: String] = [:]
    private var collapsedProjects: Set<String> = []

    private var runningCount: Int {
        containers.count(where: { $0.state == "running" })
    }

    public init() {}

    public func start() {
        update()
        timer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    public func stop() {
        timer?.cancel()
        popupPanel?.hidePopup()
    }

    private func update() {
        Task { @MainActor in
            let result = await service.fetchContainers()
            self.containers = result.containers
            if self.popupPanel?.isVisible == true {
                popupPanel?.updateContent(makePopupContent())
            }
        }
    }

    public func body() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "shippingbox.fill")
                .font(Theme.sfIconFont)
                .foregroundStyle(runningCount > 0 ? AnyShapeStyle(Theme.green) : AnyShapeStyle(.primary))
            if runningCount > 0 {
                Text("\(runningCount)")
                    .font(Theme.labelFont)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { [weak self] in
            self?.togglePopup()
        }
    }

    private func togglePopup() {
        if popupPanel?.isVisible == true {
            popupPanel?.hidePopup()
        } else {
            showPopup()
        }
    }

    private func refreshPopup() {
        popupPanel?.updateContent(makePopupContent())
        popupPanel?.resizeToFitContent()
    }

    private func makePopupContent() -> DockerPopupContent {
        let result = DockerService.Result(available: true, containers: containers)
        return DockerPopupContent(
            groups: result.groups,
            standaloneContainers: result.standaloneContainers,
            transitioningContainers: transitioningContainers,
            transitioningProjects: transitioningProjects,
            collapsedProjects: collapsedProjects,
            onToggleContainer: { [weak self] name, state in
                guard let self else { return }
                self.transitioningContainers[name] = state == "running" ? "stopping" : "starting"
                self.refreshPopup()
                Task {
                    if state == "running" {
                        _ = try? await ShellCommand.run("docker", arguments: ["stop", name])
                    } else {
                        _ = try? await ShellCommand.run("docker", arguments: ["start", name])
                    }
                    self.transitioningContainers.removeValue(forKey: name)
                    self.update()
                }
            },
            onToggleProject: { [weak self] project, allRunning in
                guard let self else { return }
                self.transitioningProjects[project] = allRunning ? "stopping" : "starting"
                for container in self.containers where container.composeProject == project {
                    self.transitioningContainers[container.name] = allRunning ? "stopping" : "starting"
                }
                self.refreshPopup()
                Task {
                    if allRunning {
                        await self.service.stopProject(project)
                    } else {
                        await self.service.startProject(project)
                    }
                    self.transitioningProjects.removeValue(forKey: project)
                    for container in self.containers where container.composeProject == project {
                        self.transitioningContainers.removeValue(forKey: container.name)
                    }
                    self.update()
                }
            },
            onToggleExpansion: { [weak self] project in
                guard let self else { return }
                if self.collapsedProjects.contains(project) {
                    self.collapsedProjects.remove(project)
                } else {
                    self.collapsedProjects.insert(project)
                }
                self.refreshPopup()
            }
        )
    }

    private func showPopup() {
        if popupPanel == nil {
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else {
            return
        }

        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: makePopupContent())
    }
}

// MARK: - DockerPopupContent

struct DockerPopupContent: View {
    let groups: [DockerService.ContainerGroup]
    let standaloneContainers: [DockerService.Container]
    let transitioningContainers: [String: String]
    let transitioningProjects: [String: String]
    let collapsedProjects: Set<String>
    let onToggleContainer: (String, String) -> Void
    let onToggleProject: (String, Bool) -> Void
    let onToggleExpansion: (String) -> Void

    private var totalContainers: Int {
        groups.reduce(0) { $0 + $1.containers.count } + standaloneContainers.count
    }

    private var totalRunning: Int {
        groups.reduce(0) { $0 + $1.runningCount }
            + standaloneContainers.count(where: { $0.state == "running" })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                PopupSectionHeader("Containers")
                Spacer()
                if totalContainers > 0 {
                    Text("\(totalRunning)/\(totalContainers) running")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 14)
                        .padding(.top, 12)
                }
            }

            if totalContainers == 0 {
                PopupEmptyState(icon: "shippingbox", message: "No containers")
            } else {
                VStack(spacing: 2) {
                    // Compose project groups
                    ForEach(groups, id: \.project) { group in
                        ComposeGroupView(
                            group: group,
                            isExpanded: !collapsedProjects.contains(group.project),
                            transitioningContainers: transitioningContainers,
                            transitioningProjects: transitioningProjects,
                            onToggleContainer: onToggleContainer,
                            onToggleProject: onToggleProject,
                            onToggleExpansion: { onToggleExpansion(group.project) }
                        )
                    }

                    // Standalone containers
                    if !standaloneContainers.isEmpty && !groups.isEmpty {
                        PopupDivider()
                    }

                    ForEach(standaloneContainers, id: \.name) { container in
                        ContainerRowView(
                            container: container,
                            transitioningContainers: transitioningContainers,
                            onToggle: onToggleContainer
                        )
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 300)
    }
}

// MARK: - ComposeGroupView

private struct ComposeGroupView: View {
    let group: DockerService.ContainerGroup
    let isExpanded: Bool
    let transitioningContainers: [String: String]
    let transitioningProjects: [String: String]
    let onToggleContainer: (String, String) -> Void
    let onToggleProject: (String, Bool) -> Void
    let onToggleExpansion: () -> Void

    private var isProjectTransitioning: Bool {
        transitioningProjects[group.project] != nil
    }

    private var projectStatusColor: Color {
        if isProjectTransitioning { return Theme.yellow }
        if group.allRunning { return Theme.green }
        if group.allStopped { return Theme.red }
        return Theme.yellow
    }

    var body: some View {
        VStack(spacing: 2) {
            // Group header with action button
            HStack(spacing: 0) {
                Button(action: onToggleExpansion) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)

                        Circle()
                            .fill(projectStatusColor)
                            .frame(width: 8, height: 8)

                        Text(group.project)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("\(group.runningCount)/\(group.containers.count)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)

                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.popupItemCornerRadius, style: .continuous))
                }
                .buttonStyle(PopupButtonStyle())

                // Start All / Stop All button
                Button(action: {
                    onToggleProject(group.project, group.allRunning)
                }) {
                    let projectState = transitioningProjects[group.project]
                    HStack(spacing: 4) {
                        if isProjectTransitioning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: group.allRunning ? "stop.fill" : "play.fill")
                                .font(.system(size: 9))
                        }
                        Text(projectState ?? (group.allRunning ? "Stop All" : "Start All"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(
                        isProjectTransitioning ? .secondary : (group.allRunning ? Theme.red : Theme.green)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                (group.allRunning ? Theme.red : Theme.green)
                                    .opacity(isProjectTransitioning ? 0.05 : 0.1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProjectTransitioning)
                .padding(.trailing, 8)
            }
            .padding(.leading, 8)

            if isExpanded {
                // Container rows
                ForEach(group.containers, id: \.name) { container in
                    ContainerRowView(
                        container: container,
                        transitioningContainers: transitioningContainers,
                        onToggle: onToggleContainer,
                        indented: true
                    )
                }
            }
        }
    }
}

// MARK: - ContainerRowView

private struct ContainerRowView: View {
    let container: DockerService.Container
    let transitioningContainers: [String: String]
    let onToggle: (String, String) -> Void
    var indented: Bool = false

    private var isTransitioning: Bool {
        transitioningContainers[container.name] != nil
    }

    private var displayState: String {
        transitioningContainers[container.name] ?? container.state
    }

    private var displayColor: Color {
        transitionColor(for: displayState) ?? container.stateColor
    }

    var body: some View {
        Button(action: { onToggle(container.name, container.state) }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(displayColor)
                    .frame(width: 8, height: 8)

                Text(displayName)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(isTransitioning ? .secondary : .primary)
                    .lineLimit(1)

                Spacer()

                PopupStatusBadge(
                    displayState,
                    color: displayColor
                )
            }
            .padding(.leading, indented ? 28 : 8)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: Theme.popupItemCornerRadius, style: .continuous))
        }
        .buttonStyle(PopupButtonStyle())
        .disabled(isTransitioning)
    }

    /// For compose containers, strip the project prefix (e.g. "myproject-web-1" → "web-1")
    private var displayName: String {
        if let project = container.composeProject,
            container.name.hasPrefix("\(project)-")
        {
            return String(container.name.dropFirst(project.count + 1))
        }
        return container.name
    }

    private func transitionColor(for state: String) -> Color? {
        switch state {
        case "starting", "stopping": Theme.yellow
        default: nil
        }
    }
}
