import AppKit
import SwiftUI

// MARK: - UpdateSheet

/// Single-pane software update sheet: shows release details and 3 actions
/// (Skip / Later / Install and Relaunch), then transitions in-place to a
/// progress view while `brew upgrade --cask` runs. On success the app
/// relaunches itself automatically.
struct UpdateSheet: View {
    let version: String
    let onClose: () -> Void

    private let updateService = AppUpdateService.shared
    private let changelogService = ChangelogService.shared

    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            Divider()
            Group {
                if updateService.updatePhase == nil {
                    detailsView
                } else {
                    installingView
                }
            }
            .padding(24)
        }
        .frame(width: 480)
        .task {
            // Wipe any leftover phase/log from a previous attempt so the
            // sheet always opens in the Confirm state.
            updateService.resetUpdateState()
            await changelogService.fetchIfNeeded()
        }
        .onChange(of: updateService.updatePhase) { _, newValue in
            if newValue == .complete {
                AppUpdateService.relaunchApp()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Software Update")
                    .font(.headline)
                Text("A new version of StatusBar is available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Details view (Confirm state)

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Version", value: "v\(version)")
                detailRow(label: "Size", value: updateService.releaseInfo?.formattedSize ?? "N/A")
                detailRow(label: "Released", value: updateService.releaseInfo?.formattedDate ?? "N/A")
            }
            whatsNewSection
            HStack {
                Spacer()
                Button("Skip") {
                    updateService.skip(version: version)
                    onClose()
                }
                Button("Later") {
                    onClose()
                }
                Button("Install and Relaunch") {
                    Task { await updateService.performUpdate() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var whatsNewSection: some View {
        let release = changelogService.release(for: version)
        DisclosureGroup("What's New") {
            Group {
                switch changelogService.state {
                case .idle,
                     .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                case .loaded:
                    if let release {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(release.entries.enumerated()), id: \.offset) { _, entry in
                                Text("• \(entry)").font(.system(size: 12))
                            }
                        }
                    } else {
                        Text("No release notes found for v\(version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                case let .failed(message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                        Link("Open on GitHub", destination: ChangelogService.githubChangelogURL)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13, weight: .medium))
        .focusEffectDisabled()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
    }

    // MARK: - Installing view

    private var installingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            phaseRow
            if updateService.updatePhase != .complete {
                ProgressView(value: updateService.updateProgress)
                    .progressViewStyle(.linear)
            }
            DisclosureGroup("Show Details", isExpanded: $showLog) {
                logView
                    .padding(.top, 6)
            }
            .font(.system(size: 12, weight: .medium))
            HStack {
                if case .failed = updateService.updatePhase,
                   let releasesURL = URL(string: "https://github.com/hytfjwr/StatusBar/releases/latest")
                {
                    Link("View Releases", destination: releasesURL)
                        .font(.system(size: 12))
                }
                Spacer()
                installingActionButton
            }
        }
    }

    @ViewBuilder
    private var phaseRow: some View {
        if let phase = updateService.updatePhase {
            HStack(spacing: 8) {
                phaseIcon(phase)
                Text(phase.label)
                    .font(.system(size: 13))
                    .foregroundStyle(phaseColor(phase))
            }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(updateService.updateLog)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                Color.clear.frame(height: 1).id("logAnchor")
            }
            .frame(height: 120)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .defaultScrollAnchor(.bottom)
            .onChange(of: updateService.updateLog) {
                proxy.scrollTo("logAnchor", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var installingActionButton: some View {
        switch updateService.updatePhase {
        case .complete:
            // Relaunch is triggered automatically via onChange; show a static label
            // for the brief window before NSApp terminates.
            ProgressView().controlSize(.small)
        case .failed:
            Button("Close") {
                updateService.resetUpdateState()
                onClose()
            }
        default:
            Button("Cancel") {
                updateService.cancelUpdate()
                onClose()
            }
        }
    }

    @ViewBuilder
    private func phaseIcon(_ phase: AppUpdateService.UpdatePhase) -> some View {
        switch phase {
        case .preparing,
             .updating:
            ProgressView().controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
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
