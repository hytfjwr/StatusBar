# Contributing to StatusBar

Thank you for your interest in contributing to StatusBar. This guide will help you get set up and submit your first pull request.

## Requirements

- **macOS 26+**
- **Xcode 26 beta+**
- **Swift 6.2** (ships with Xcode 26 beta)

StatusBar uses Swift 6 strict concurrency. Make sure your Xcode toolchain supports it before starting.

## Build & Run

```bash
# Clone the repository
git clone https://github.com/hytfjwr/macos-status-bar.git
cd macos-status-bar

# Debug build and run
make run

# Run tests
make test

# Release build
make release

# Create .app bundle
make bundle
```

## StatusBarKit Dependency

StatusBar depends on [StatusBarKit](https://github.com/hytfjwr/StatusBarKit), a separate package that provides the widget protocol and shared types used by the plugin system.

For local development against a modified StatusBarKit, use SPM's edit mode:

```bash
swift package edit StatusBarKit
```

This clones StatusBarKit into `Packages/StatusBarKit/` where you can make changes. When done:

```bash
swift package unedit StatusBarKit
```

## Plugin Development

StatusBar supports third-party plugins loaded as dylibs via `dlopen()`. Plugins conform to the `StatusBarWidget` protocol defined in StatusBarKit.

For full details on plugin architecture, ABI stability, and distribution, see `PLUGIN_ARCHITECTURE.md`.

## Code Style

SwiftLint and SwiftFormat are configured as SPM build plugins and run automatically during builds. No manual setup is needed. Just make sure your code compiles cleanly with `swift build`.

Key conventions:
- UI code is `@MainActor`
- Services are `nonisolated` and run on background queues
- Async shell calls go through `ShellCommand.swift` (5-second timeout)

## Submitting a Pull Request

1. Fork the repository and create a feature branch from `main`.
2. Make your changes.
3. Ensure `swift build` succeeds with no warnings.
4. Ensure `swift test` passes.
5. Open a pull request against `main` with a clear description of your changes and motivation.

Keep PRs focused on a single concern. If you're fixing a bug and adding a feature, split them into separate PRs.

## Reporting Issues

Use [GitHub Issues](https://github.com/hytfjwr/macos-status-bar/issues) for bug reports and feature requests. Include your macOS version and steps to reproduce when reporting bugs.
