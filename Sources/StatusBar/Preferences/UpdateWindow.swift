import AppKit
import SwiftUI

// MARK: - UpdateWindow

@MainActor
final class UpdateWindow {
    static let shared = UpdateWindow()

    private var window: NSWindow?

    private init() {}

    func show(version: String) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        AppUpdateService.shared.resetUpdateState()

        let view = UpdateView(version: version) {
            self.window?.close()
        }
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

// MARK: - UpdateView

struct UpdateView: View {
    let version: String
    let onClose: () -> Void

    private let updateService = AppUpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            phaseIndicator
            progressBar
            logOutput
            actionButtons
        }
        .padding(20)
        .frame(width: 480, height: 360)
        .task {
            await updateService.performUpdate()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Updating StatusBar")
                    .font(.headline)
                Text("v\(AppUpdateService.appVersion) → v\(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Phase Indicator

    @ViewBuilder
    private var phaseIndicator: some View {
        if let phase = updateService.updatePhase {
            HStack(spacing: 8) {
                phaseIcon(phase)
                Text(phase.label)
                    .font(.system(size: 13))
                    .foregroundStyle(phaseColor(phase))
            }
        }
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        if updateService.updatePhase != nil {
            ProgressView(value: updateService.updateProgress)
                .progressViewStyle(.linear)
        }
    }

    // MARK: - Log Output

    private var logOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(updateService.updateLog)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)

                Color.clear
                    .frame(height: 1)
                    .id("logAnchor")
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: updateService.updateLog) {
                proxy.scrollTo("logAnchor", anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            if case .failed = updateService.updatePhase,
               let releasesURL = URL(string: "https://github.com/hytfjwr/StatusBar/releases/latest")
            {
                Link("View Releases", destination: releasesURL)
                    .font(.system(size: 12))
            }

            Spacer()

            switch updateService.updatePhase {
            case .complete:
                Button("Restart") {
                    AppUpdateService.relaunchApp()
                }
                .keyboardShortcut(.defaultAction)

            case .failed:
                Button("Close") {
                    onClose()
                }

            default:
                Button("Cancel") {
                    updateService.cancelUpdate()
                    onClose()
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func phaseIcon(_ phase: AppUpdateService.UpdatePhase) -> some View {
        switch phase {
        case .preparing,
             .updating:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func phaseColor(_ phase: AppUpdateService.UpdatePhase) -> Color {
        switch phase {
        case .preparing,
             .updating: .secondary
        case .complete: .green
        case .failed: .red
        }
    }
}
