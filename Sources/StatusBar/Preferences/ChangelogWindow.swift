import AppKit
import SwiftUI

// MARK: - ChangelogWindow

@MainActor
final class ChangelogWindow {
    static let shared = ChangelogWindow()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ChangelogView()
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Changelog"
        window.contentView = hostingView
        window.minSize = NSSize(width: 400, height: 320)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

// MARK: - ChangelogView

struct ChangelogView: View {
    private let changelogService = ChangelogService.shared

    var body: some View {
        Group {
            switch changelogService.state {
            case .idle,
                 .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading changelog…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .loaded(releases):
                if releases.isEmpty {
                    emptyView
                } else {
                    releaseList(releases)
                }

            case let .failed(message):
                errorView(message)
            }
        }
        .task {
            await changelogService.fetchIfNeeded()
        }
    }

    // MARK: - Release List

    private func releaseList(_ releases: [ChangelogRelease]) -> some View {
        List {
            ForEach(releases) { release in
                releaseSection(release)
            }
        }
        .listStyle(.plain)
    }

    private func releaseSection(_ release: ChangelogRelease) -> some View {
        Section {
            ForEach(Array(release.entries.enumerated()), id: \.offset) { _, entry in
                Text("• \(entry)")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .listRowSeparator(.hidden)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("v\(release.version)")
                    .font(.system(size: 14, weight: .semibold))
                Text(release.date)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Empty / Error States

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No changelog entries found.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Failed to load changelog")
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await changelogService.retry() }
                }
                .controlSize(.small)

                Link("Open on GitHub", destination: ChangelogService.githubChangelogURL)
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
