import StatusBarKit
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    let onDismiss: () -> Void

    @State private var page: OnboardingPage = .welcome

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch page {
                case .welcome:
                    WelcomePage()
                case .widgets:
                    WidgetPickerPage(registry: WidgetRegistry.shared)
                case .menuBarSetup:
                    MenuBarSetupPage()
                case .tips:
                    TipsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if page != .welcome {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            page = page.previous
                        }
                    }
                }

                Spacer()

                // Page indicator
                HStack(spacing: 6) {
                    ForEach(OnboardingPage.allCases) { p in
                        Circle()
                            .fill(p == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if page == .tips {
                    Button("Get Started") {
                        UserDefaults.standard.set(true, forKey: OnboardingKeys.hasCompleted)
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            page = page.next
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: - OnboardingPage

private enum OnboardingPage: String, CaseIterable, Identifiable {
    case welcome
    case widgets
    case menuBarSetup
    case tips

    var id: Self {
        self
    }

    var next: Self {
        switch self {
        case .welcome: .widgets
        case .widgets: .menuBarSetup
        case .menuBarSetup: .tips
        case .tips: .tips
        }
    }

    var previous: Self {
        switch self {
        case .welcome: .welcome
        case .widgets: .welcome
        case .menuBarSetup: .widgets
        case .tips: .menuBarSetup
        }
    }
}

// MARK: - WelcomePage

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "menubar.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to StatusBar")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A native macOS status bar replacement\nbuilt with Swift and Liquid Glass.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            featureGrid
                .padding(.horizontal, 40)

            Spacer()
        }
        .padding(24)
    }

    private var featureGrid: some View {
        HStack(spacing: 24) {
            FeatureCard(
                icon: "square.grid.2x2",
                title: "Widgets",
                description: "CPU, memory, battery, network, and more"
            )
            FeatureCard(
                icon: "paintbrush",
                title: "Customizable",
                description: "Colors, fonts, layout — all configurable"
            )
            FeatureCard(
                icon: "doc.text",
                title: "YAML Config",
                description: "Edit config.yml for instant hot-reload"
            )
        }
    }
}

// MARK: - FeatureCard

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - WidgetPickerPage

private struct WidgetPickerPage: View {
    let registry: WidgetRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Your Widgets")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Toggle the widgets you want on your bar. You can change this anytime in Preferences.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(registry.layout) { entry in
                        WidgetToggleRow(
                            entry: entry,
                            displayName: registry.displayName(for: entry.id),
                            sfSymbolName: registry.sfSymbolName(for: entry.id),
                            onToggle: { visible in
                                registry.setVisible(visible, for: entry.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - WidgetToggleRow

private struct WidgetToggleRow: View {
    let entry: WidgetLayoutEntry
    let displayName: String
    let sfSymbolName: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sfSymbolName)
                .font(.system(size: 13))
                .foregroundStyle(entry.isVisible ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 24)

            Text(displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(entry.isVisible ? .primary : .secondary)

            Spacer()

            Text(entry.section.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

            Toggle("", isOn: Binding(
                get: { entry.isVisible },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            entry.isVisible ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

// MARK: - MenuBarSetupPage

private struct MenuBarSetupPage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Hide the macOS Menu Bar")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("StatusBar works best when the built-in macOS menu bar is hidden.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            stepsView

            Button(action: openControlCenterSettings) {
                Label("Open System Settings", systemImage: "gear")
            }
            .controlSize(.large)

            Spacer()
        }
        .padding(24)
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepRow(number: 1, text: "System Settings → Control Center")
            StepRow(number: 2, text: "Set \"Automatically hide and show the menu bar\" to **Always**")
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openControlCenterSettings() {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - StepRow

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - TipsPage

private struct TipsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Tips")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("A few things to help you get started.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 12) {
                TipRow(
                    icon: "folder",
                    color: .blue,
                    title: "Config File",
                    description: "Your settings are stored at ~/.config/statusbar/config.yml."
                        + " Edit it directly — changes are applied instantly via hot-reload."
                )
                TipRow(
                    icon: "arrow.triangle.2.circlepath",
                    color: .green,
                    title: "Hot Reload",
                    description: "Save config.yml and your bar updates immediately. No restart needed."
                )
                TipRow(
                    icon: "square.on.square.dashed",
                    color: .purple,
                    title: "Presets",
                    description: "Save and switch between different configurations using Preferences > Presets."
                )
                TipRow(
                    icon: "puzzlepiece.extension",
                    color: .orange,
                    title: "Plugins",
                    description: "Extend with native dylib plugins. Manage them from Preferences > Plugins."
                )
                TipRow(
                    icon: "gearshape",
                    color: .secondary,
                    title: "Preferences",
                    description: "Right-click the bar or use the Apple menu widget to open Preferences anytime."
                )
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - TipRow

private struct TipRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
