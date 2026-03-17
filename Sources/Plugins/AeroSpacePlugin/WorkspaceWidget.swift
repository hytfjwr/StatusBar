import AppKit
import Combine
import StatusBarKit
import SwiftUI

// MARK: - WorkspaceWidget

@MainActor
@Observable
public final class WorkspaceWidget: StatusBarWidget {
    public let id = "workspace"
    public let position: WidgetPosition = .left
    public let updateInterval: TimeInterval? = 10
    public var sfSymbolName: String { "square.grid.3x3" }

    private var timer: AnyCancellable?
    private let service = AeroSpaceService()
    private var workspaces: [WorkspaceInfo] = []
    private var focusedWorkspace = ""
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var updateTask: Task<Void, Never>?
    private var showAppIcons = true
    private var appIconSize = 16.0
    private var showEmptySpaces = false

    public struct WorkspaceInfo: Identifiable {
        public let id: String
        public let apps: [String]
        public let isFocused: Bool
        public let monitorID: Int?
    }

    public init() {}

    public func start() {
        applySettings()
        update()
        restartTimer()
        startFileMonitoring()
        observeSettings()
    }

    public func stop() {
        timer?.cancel()
        stopFileMonitoring()
    }

    public var hasSettings: Bool { true }

    public func settingsBody() -> some View {
        WorkspaceWidgetSettings()
    }

    private func applySettings() {
        let settings = WorkspaceSettings.shared
        showAppIcons = settings.showAppIcons
        appIconSize = settings.appIconSize
        showEmptySpaces = settings.showEmptySpaces
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = WorkspaceSettings.shared.updateInterval
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    private func observeSettings() {
        withObservationTracking {
            let s = WorkspaceSettings.shared
            _ = s.updateInterval
            _ = s.showAppIcons
            _ = s.appIconSize
            _ = s.showEmptySpaces
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySettings()
                self?.restartTimer()
                self?.update()
                self?.observeSettings()
            }
        }
    }

    private func startFileMonitoring() {
        let path = AeroSpaceService.focusedWorkspaceFile

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onFileChanged()
        }

        let capturedFD = fileDescriptor
        source.setCancelHandler {
            if capturedFD >= 0 {
                close(capturedFD)
            }
        }

        source.resume()
        fileMonitorSource = source
    }

    private func stopFileMonitoring() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    private func onFileChanged() {
        let path = AeroSpaceService.focusedWorkspaceFile
        Task.detached {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            let newFocused = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newFocused.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self, newFocused != focusedWorkspace else { return }
                focusedWorkspace = newFocused
                update()
            }
        }
    }

    private func update() {
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            let info = await service.fetchWorkspaces()
            guard !Task.isCancelled else { return }
            self.focusedWorkspace = info.focused
            self.workspaces = info.workspaces.compactMap { ws in
                if !self.showEmptySpaces, ws.apps.isEmpty, ws.id != info.focused {
                    return nil
                }
                return WorkspaceInfo(
                    id: ws.id,
                    apps: ws.apps,
                    isFocused: ws.id == info.focused,
                    monitorID: ws.monitorID
                )
            }
        }
    }

    public func body() -> some View {
        WorkspaceContainerView(
            workspaces: workspaces,
            showAppIcons: showAppIcons,
            appIconSize: appIconSize
        )
    }
}

// MARK: - WorkspaceContainerView

private struct WorkspaceContainerView: View {
    let workspaces: [WorkspaceWidget.WorkspaceInfo]
    let showAppIcons: Bool
    let appIconSize: CGFloat
    @Environment(\.screenIndex) private var screenIndex

    init(workspaces: [WorkspaceWidget.WorkspaceInfo], showAppIcons: Bool, appIconSize: Double) {
        self.workspaces = workspaces
        self.showAppIcons = showAppIcons
        self.appIconSize = CGFloat(appIconSize)
    }

    var body: some View {
        // aerospace monitor ID is 1-based, screenIndex is 0-based
        let monitor = screenIndex + 1
        let filtered = workspaces.filter { ws in
            (ws.monitorID ?? 1) == monitor
        }
        HStack(spacing: 4) {
            ForEach(filtered) { ws in
                WorkspaceItemView(workspace: ws, showAppIcons: showAppIcons, appIconSize: appIconSize) {
                    Task {
                        try? await ShellCommand.run("aerospace", arguments: ["workspace", ws.id])
                    }
                }
            }
        }
    }
}

// MARK: - WorkspaceItemView

private struct WorkspaceItemView: View {
    let workspace: WorkspaceWidget.WorkspaceInfo
    let showAppIcons: Bool
    let appIconSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(workspace.id)
                .font(Theme.labelFont)

            if showAppIcons, !workspace.apps.isEmpty {
                ForEach(workspace.apps, id: \.self) { app in
                    AppIconView(appName: app, size: appIconSize)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .foregroundStyle(workspace.isFocused ? .primary : .secondary)
        .glassEffect(
            workspace.isFocused ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: 5)
        )
        .animation(.easeInOut(duration: 0.2), value: workspace.isFocused)
        .onTapGesture { onTap() }
    }
}

// MARK: - WorkspaceWidgetSettings

struct WorkspaceWidgetSettings: View {
    @State private var updateInterval: Double
    @State private var showAppIcons: Bool
    @State private var appIconSize: Double
    @State private var showEmptySpaces: Bool

    init() {
        let s = WorkspaceSettings.shared
        _updateInterval = State(initialValue: s.updateInterval)
        _showAppIcons = State(initialValue: s.showAppIcons)
        _appIconSize = State(initialValue: s.appIconSize)
        _showEmptySpaces = State(initialValue: s.showEmptySpaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Update Interval
            VStack(alignment: .leading, spacing: 8) {
                Text("Update Interval")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Update Interval", selection: $updateInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: updateInterval) { _, newValue in
                    WorkspaceSettings.shared.updateInterval = newValue
                }
            }

            Divider()

            // Display
            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Toggle("Show App Icons", isOn: $showAppIcons)
                    .onChange(of: showAppIcons) { _, newValue in
                        WorkspaceSettings.shared.showAppIcons = newValue
                    }

                if showAppIcons {
                    HStack {
                        Text("Icon Size")
                        Spacer()
                        Picker("", selection: $appIconSize) {
                            Text("12").tag(12.0)
                            Text("14").tag(14.0)
                            Text("16").tag(16.0)
                            Text("18").tag(18.0)
                            Text("20").tag(20.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    .onChange(of: appIconSize) { _, newValue in
                        WorkspaceSettings.shared.appIconSize = newValue
                    }
                }

                Toggle("Show Empty Workspaces", isOn: $showEmptySpaces)
                    .onChange(of: showEmptySpaces) { _, newValue in
                        WorkspaceSettings.shared.showEmptySpaces = newValue
                    }
            }
        }
    }
}
