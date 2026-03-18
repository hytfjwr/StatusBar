# Plugin Architecture

This document describes the dylib-based plugin system for the macOS status bar application. Plugins are independently compiled dynamic libraries that the host application loads at runtime via `dlopen()`.

## Overview

The plugin system allows third-party developers to add widgets to the status bar without modifying the host application. The architecture is built on three pillars:

1. **StatusBarKit** -- A dynamic framework (`libStatusBarKit.dylib`) compiled with Library Evolution Mode. It defines the protocols and types shared between the host and plugins.
2. **Plugin bundles** (`.statusplugin`) -- Directories containing a compiled dylib and a `manifest.json` metadata file.
3. **DylibPluginLoader** -- The host-side loader that scans `~/.config/statusbar/plugins/`, validates manifests, verifies integrity, calls `dlopen()`, resolves the factory symbol, and registers widgets.

The flow: a plugin author implements `StatusBarPlugin`, exposes a `@_cdecl` factory function that returns a `PluginBox`, builds a `.dylib`, bundles it with a manifest, and distributes it as a `.statusplugin.zip`. The host discovers, validates, loads, and renders it.

## Plugin Protocol

### StatusBarPlugin

Defined in `StatusBarKit/Sources/StatusBarKit/PluginProtocol.swift`:

```swift
@MainActor
public protocol StatusBarPlugin {
    var manifest: PluginManifest { get }
    var widgets: [any StatusBarWidget] { get }
    func register(to registry: any WidgetRegistryProtocol)
}
```

- `manifest` -- Provides the plugin's in-memory metadata (id, name, version).
- `widgets` -- Returns the widget instances this plugin provides, in display order.
- `register(to:)` -- Has a default implementation that iterates `widgets` and calls `registry.register(_:)` for each. Override for custom registration logic.

### StatusBarWidget

Each widget conforms to this protocol (from `WidgetProtocol.swift`):

```swift
@MainActor
public protocol StatusBarWidget: AnyObject {
    associatedtype WidgetBody: View
    associatedtype SettingsBody: View = EmptyView
    var id: String { get }
    var position: WidgetPosition { get }       // .left, .center, .right
    var updateInterval: TimeInterval? { get }  // nil = event-driven
    var sfSymbolName: String { get }
    func start()
    func stop()
    @ViewBuilder func body() -> WidgetBody
    @ViewBuilder func settingsBody() -> SettingsBody
}
```

Widgets return concrete `View` types. The host wraps them in `AnyStatusBarWidget` for type-erased storage and rendering.

### PluginBox

The bridge between `nonisolated` C-convention factory functions and `@MainActor`-isolated plugin construction:

```swift
public final class PluginBox: @unchecked Sendable {
    public let factory: @MainActor () -> any StatusBarPlugin
    public init(_ factory: @escaping @MainActor () -> any StatusBarPlugin)
}
```

The `@_cdecl` factory function creates a `PluginBox` wrapping a closure that constructs the plugin. The host calls `box.factory()` on the main actor after `dlopen()` completes.

### PluginManifest (in-memory)

```swift
public struct PluginManifest: Sendable {
    public let id: String       // e.g. "com.statusbar.aerospace"
    public let name: String     // e.g. "AeroSpace"
    public let version: String  // e.g. "1.0.0"
}
```

This is the lightweight in-memory metadata struct returned by `StatusBarPlugin.manifest`. Not to be confused with `DylibPluginManifest` which is the on-disk JSON manifest.

## Plugin Lifecycle

### 1. Discovery

On launch, `DylibPluginLoader.loadAll(into:)` scans `~/.config/statusbar/plugins/` for directories with the `.statusplugin` extension. It also consults `PluginStore` (backed by `~/.config/statusbar/plugins/registry.json`) and skips bundles whose records have `enabled: false`.

### 2. Manifest Validation

For each bundle, the loader reads `manifest.json` and decodes it into `DylibPluginManifest`:

```json
{
  "id": "com.statusbar.aerospace",
  "name": "AeroSpacePlugin",
  "version": "0.1.0",
  "statusBarKitVersion": "1.0.0",
  "swiftVersion": "6.2",
  "entrySymbol": "createStatusBarPlugin",
  "sha256": "a1b2c3..."
}
```

Field validation rules:
- `id` -- alphanumeric, dots, hyphens, underscores only (`^[a-zA-Z0-9._-]+$`)
- `entrySymbol` -- valid C identifier (`^[a-zA-Z_][a-zA-Z0-9_]*$`)
- `version` -- alphanumeric with dots, hyphens, underscores (`^[a-zA-Z0-9._-]+$`)
- `name` -- alphanumeric with dots, hyphens, underscores, spaces (`^[a-zA-Z0-9._\- ]+$`)

Duplicate plugin IDs (already loaded) are rejected.

### 3. Version Compatibility Check

The loader compares `statusBarKitVersion` from the manifest against the host's `statusBarKitVersion` constant using `SemanticVersion.isCompatible(with:)`:

- **Major versions must match exactly.** A major version bump indicates a breaking API change; plugins must be rebuilt.
- **Plugin minor version must be <= host minor version.** A plugin built against 1.2.0 can run on host 1.3.0 (host has all APIs the plugin needs) but not on host 1.1.0 (host lacks APIs added in 1.2).
- **Patch versions are ignored** for compatibility purposes.

Dev-mode loading (`loadDev(bundleURL:into:)`) skips this check for local development convenience.

### 4. SHA-256 Integrity Verification

If the manifest includes a `sha256` field, the loader computes the SHA-256 hash of the `.dylib` file and compares it. A mismatch throws `PluginLoadError.sha256Mismatch`. If `sha256` is absent, a warning is logged and loading proceeds.

### 5. dlopen and Symbol Resolution

```
dlopen(dylibURL.path, RTLD_NOW | RTLD_LOCAL)
```

- `RTLD_NOW` -- Resolve all symbols immediately; fail fast if dependencies are missing.
- `RTLD_LOCAL` -- Keep symbols scoped to this handle to avoid symbol collisions between plugins.

The loader then calls `dlsym(handle, entrySymbol)` to find the factory function. The default entry symbol is `"createStatusBarPlugin"`.

### 6. Factory Invocation

The resolved symbol is cast to `@convention(c) () -> UnsafeMutableRawPointer` and called. The returned raw pointer is converted via `Unmanaged<AnyObject>.fromOpaque(_:).takeRetainedValue()` and cast to `PluginBox`. Ownership transfers to the host (`takeRetainedValue` balances the `passRetained` in the plugin's factory).

### 7. Widget Registration

`box.factory()` is called on `@MainActor` to create the `StatusBarPlugin` instance. Then `WidgetRegistry.registerPlugin(_:)` calls the plugin's `register(to:)` method, which by default registers each widget.

### 8. Retention

The host retains:
- The `dlopen` handle in `loadedHandles[pluginID]`
- The `StatusBarPlugin` instance in `loadedPlugins[pluginID]`

Both must remain alive for the plugin's lifetime. On unload (`markForRemoval`), the plugin's widgets are stopped first, the plugin reference is released (allowing ARC to deallocate plugin objects whose code lives in the dylib), and then `dlclose()` is called.

## ABI Stability

### Library Evolution Mode

StatusBarKit is compiled with `-enable-library-evolution`, which instructs the Swift compiler to generate a stable ABI. This means:

- The `.swiftinterface` files define the module's public API in a compiler-readable format.
- Adding new public API (methods, properties, protocol requirements with defaults) is a source- and ABI-compatible change.
- The dylib uses `@rpath/libStatusBarKit.dylib` as its install name, resolved at runtime via the host's rpath settings.

### Semantic Versioning Contract

| Change type | Version bump | Plugin impact |
|---|---|---|
| Bug fix, no API change | Patch (1.0.x) | Compatible. No rebuild needed. |
| New public API added | Minor (1.x.0) | Compatible. Old plugins still work. New plugins using the new API require the new minor version. |
| Public API removed or changed | Major (x.0.0) | **Breaking.** All plugins must be rebuilt against the new major version. |

### Swift Compiler Version

Plugins must be built with the same Swift compiler major version as the host. The `swiftVersion` field in the manifest is informational; the actual ABI compatibility is enforced by the Swift runtime and Library Evolution's `.swiftinterface` contracts.

## Distribution

### Bundle Format

A `.statusplugin` bundle is a flat directory:

```
aerospace.statusplugin/
  manifest.json       # DylibPluginManifest (required)
  plugin.dylib        # The compiled dynamic library (any .dylib file)
```

The loader finds the first `.dylib` file in the bundle directory. The naming convention is `plugin.dylib` but any `.dylib` filename works.

### Packaging

Bundles are distributed as `.statusplugin.zip` archives. The archive must contain the `.statusplugin` directory at its root level:

```
aerospace.statusplugin.zip
  aerospace.statusplugin/
    manifest.json
    plugin.dylib
```

### GitHub Releases Integration

`GitHubPluginInstaller` handles one-click installation from GitHub repositories:

1. **Parse** the GitHub URL (accepts `https://github.com/owner/repo`, `owner/repo`, etc.)
2. **Fetch** the latest release via the GitHub API (`/repos/{owner}/{repo}/releases/latest`)
3. **Find** the `.statusplugin.zip` asset in the release
4. **Download** the asset (HTTPS only, restricted to trusted hosts: `github.com`, `api.github.com`, `objects.githubusercontent.com`)
5. **Extract** to a temporary directory using `/usr/bin/unzip`
6. **Validate** -- Path traversal check on all extracted files, manifest parsing, version compatibility check
7. **Install** -- Atomic copy/replace to `~/.config/statusbar/plugins/`
8. **Register** in `PluginStore` with the GitHub URL for future update checks

### Update Checking

`GitHubPluginInstaller.checkForUpdates()` iterates all installed plugins with a `githubURL`, fetches the latest release tag, and compares against the installed version. Returns an array of `UpdateInfo` for plugins with available updates.

### Plugin Store

`PluginStore` maintains `~/.config/statusbar/plugins/registry.json` with installed plugin metadata:

```json
{
  "plugins": [
    {
      "id": "com.statusbar.aerospace",
      "name": "AeroSpacePlugin",
      "version": "0.1.0",
      "githubURL": "https://github.com/owner/statusbar-plugin-aerospace",
      "bundleName": "aerospace",
      "installedAt": "2026-01-15T10:30:00Z",
      "enabled": true,
      "isLocal": false
    }
  ]
}
```

The registry file has `0600` permissions (owner-only read/write). If the registry is corrupted (fails to decode), plugin loading is aborted entirely to prevent re-enabling user-disabled plugins.

## Creating a Plugin

### 1. Package.swift

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyPlugin",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MyPlugin", type: .dynamic, targets: ["MyPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hytfjwr/StatusBarKit", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MyPlugin",
            dependencies: [
                .product(name: "StatusBarKit", package: "StatusBarKit"),
            ]
        ),
    ]
)
```

Key points:
- The product type must be `.dynamic` to produce a `.dylib`.
- Depend on `StatusBarKit` from the GitHub package registry.

### 2. Implement the Plugin

```swift
import StatusBarKit
import SwiftUI

// -- Widget --

@MainActor
final class HelloWidget: StatusBarWidget {
    let id = "hello"
    let position = WidgetPosition.right
    let updateInterval: TimeInterval? = nil

    func start() {}
    func stop() {}

    func body() -> some View {
        Text("Hello, Plugin!")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
    }
}

// -- Plugin --

@MainActor
public struct HelloPlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.example.hello",
        name: "Hello"
    )

    public let widgets: [any StatusBarWidget]

    public init() {
        widgets = [HelloWidget()]
    }
}

// -- Factory (must be top-level) --

@_cdecl("createStatusBarPlugin")
public func createStatusBarPlugin() -> UnsafeMutableRawPointer {
    let box = PluginBox { HelloPlugin() }
    return Unmanaged.passRetained(box).toOpaque()
}
```

The `@_cdecl` function is the entry point that `DylibPluginLoader` resolves via `dlsym`. It must:
- Be a public top-level function (not a method)
- Use `@_cdecl("symbolName")` matching the manifest's `entrySymbol`
- Return `UnsafeMutableRawPointer` via `Unmanaged.passRetained(box).toOpaque()`
- Wrap the plugin construction in a `PluginBox` closure (defers `@MainActor` construction to the host)

### 3. Build and Bundle

A `Makefile` simplifies the build/bundle/install cycle:

```makefile
PLUGIN_NAME := MyPlugin
PLUGIN_ID := com.example.hello
VERSION := 0.1.0
STATUSBARKIT_VERSION := 1.0.0
SWIFT_VERSION := 6.2
BUNDLE_NAME := hello

BUILD_DIR := .build/release
BUNDLE_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).statusplugin
DYLIB := $(BUILD_DIR)/lib$(PLUGIN_NAME).dylib
ZIP_FILE := $(BUILD_DIR)/$(BUNDLE_NAME).statusplugin.zip
PLUGINS_DIR := $(HOME)/.config/statusbar/plugins

.PHONY: build bundle package dev clean

build:
	swift build -c release

bundle: build
	mkdir -p $(BUNDLE_DIR)
	cp $(DYLIB) $(BUNDLE_DIR)/plugin.dylib
	@echo '{\n  "id": "$(PLUGIN_ID)",\n  "name": "$(PLUGIN_NAME)",\n  "version": "$(VERSION)",\n  "statusBarKitVersion": "$(STATUSBARKIT_VERSION)",\n  "swiftVersion": "$(SWIFT_VERSION)",\n  "entrySymbol": "createStatusBarPlugin"\n}' > $(BUNDLE_DIR)/manifest.json
	@echo "Bundle created: $(BUNDLE_DIR)"

package: bundle
	cd $(BUILD_DIR) && zip -r $(BUNDLE_NAME).statusplugin.zip $(BUNDLE_NAME).statusplugin/
	@echo "Package created: $(ZIP_FILE)"

dev: bundle
	mkdir -p $(PLUGINS_DIR)
	rm -rf $(PLUGINS_DIR)/$(BUNDLE_NAME).statusplugin
	cp -r $(BUNDLE_DIR) $(PLUGINS_DIR)/
	@echo "Installed to $(PLUGINS_DIR)/$(BUNDLE_NAME).statusplugin"

clean:
	swift package clean
	rm -rf $(BUILD_DIR)/$(BUNDLE_NAME).statusplugin $(ZIP_FILE)
```

Development workflow:

```bash
# Build and install locally for testing
make dev

# Restart the status bar app to pick up the plugin
pkill -f StatusBar && swift build && .build/debug/StatusBar

# Package for distribution
make package
# Upload .build/release/hello.statusplugin.zip to a GitHub Release
```

### 4. Distribute via GitHub Releases

1. Create a GitHub repository for your plugin.
2. Tag a release (e.g., `v0.1.0`).
3. Attach the `.statusplugin.zip` file as a release asset.
4. Users install via the Preferences > Plugins UI by entering your repository URL.

## Security Considerations

### Dynamic Library Loading Risks

Loading arbitrary dylibs via `dlopen()` executes code with the full privileges of the host process. A malicious plugin can:
- Access all files readable by the user
- Make network requests
- Interact with system APIs (accessibility, camera, etc.)
- Tamper with the host process memory

### Mitigations

**Entitlement: `com.apple.security.cs.disable-library-validation`**

The host application has the `disable-library-validation` entitlement in `StatusBar.entitlements`. This is required because plugins are not signed with the same team identity as the host. Without this entitlement, macOS would refuse to `dlopen()` third-party dylibs. This entitlement weakens the code signing trust chain.

**Manifest field validation.** All manifest fields are validated against strict regex patterns before use. The `id`, `entrySymbol`, `version`, and `name` fields reject characters that could enable path traversal or injection attacks.

**SHA-256 integrity verification.** If a manifest includes a `sha256` hash, the loader verifies the dylib's hash before loading it. This detects tampering after download but does not establish trust in the original author.

**Download URL allowlisting.** `GitHubPluginInstaller` only downloads from a hardcoded set of trusted HTTPS hosts (`github.com`, `api.github.com`, `objects.githubusercontent.com`) to prevent SSRF attacks.

**Path traversal protection.** After extracting a downloaded zip, all extracted file paths are verified to stay within the temporary directory.

**Atomic file replacement.** Plugin installation uses `FileManager.replaceItemAt(_:withItemAt:)` to prevent TOCTOU race conditions.

**Registry file permissions.** The plugin store (`registry.json`) is written with `0600` permissions.

**Duplicate ID rejection.** A plugin whose ID is already loaded is rejected to prevent one plugin from shadowing another.

### Trust Model

The current trust model is **user-trust-based**: the user decides which plugins to install and enables them explicitly. There is no code signing verification of plugin dylibs, no sandboxing of loaded plugin code, and no permission system restricting what plugins can do once loaded. Users should only install plugins from sources they trust.
