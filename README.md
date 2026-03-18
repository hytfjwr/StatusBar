# StatusBar

> A Swift-native custom status bar for macOS, inspired by [sketchybar](https://github.com/FelixKratz/SketchyBar).

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26+-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Getting Started

### Requirements

- macOS 26+
- Xcode 26 beta+ ([download](https://developer.apple.com/download/))
- Swift 6.2

### Build & Run

```bash
# Debug build & run
make run

# Release build
make release

# Create .app bundle
make bundle

# Package for distribution
make package
```

## Configuration

A default config is generated at `~/.config/statusbar/config.yml` on first launch. The file is hot-reloaded — edits are applied instantly without restarting. All settings are also available through the Preferences window (Apple Menu > Preferences).

### Bar

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `height` | number | 40 | Bar height in pixels |
| `cornerRadius` | number | 12 | Corner radius in pixels |
| `margin` | number | 8 | Margin from screen edges |
| `yOffset` | number | 4 | Vertical offset from top |
| `widgetSpacing` | number | 6 | Space between widgets |
| `widgetPaddingH` | number | 6 | Horizontal padding inside each widget |

### Appearance

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `accent` | hex color | `#007AFF` | Accent color |
| `green` | hex color | `#34C759` | Green semantic color |
| `yellow` | hex color | `#FF9F0A` | Yellow semantic color |
| `red` | hex color | `#FF3B30` | Red semantic color |
| `cyan` | hex color | `#64D2FF` | Cyan semantic color |
| `purple` | hex color | `#BF5AF2` | Purple semantic color |
| `barTint` | hex color | `#000000` | Bar background tint color |
| `barTintOpacity` | number | 0.0 | Bar tint opacity (0.0–1.0) |
| `textPrimaryOpacity` | number | 1.0 | Primary text opacity |
| `textSecondaryOpacity` | number | 0.55 | Secondary text opacity |
| `textTertiaryOpacity` | number | 0.30 | Tertiary text opacity |
| `shadowEnabled` | bool | true | Drop shadow on bar |
| `popupCornerRadius` | number | 10 | Popup corner radius |
| `popupPadding` | number | 12 | Popup internal padding |

### Typography

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `iconFontSize` | number | 13 | Icon font size (pt) |
| `labelFontSize` | number | 13 | Label font size (pt) |
| `smallFontSize` | number | 11 | Small text font size (pt) |
| `monoFontSize` | number | 12 | Monospace font size (pt) |

### Graphs

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `width` | number | 30 | Graph width in pixels |
| `height` | number | 14 | Graph height in pixels |
| `dataPoints` | integer | 50 | Number of data points to display |
| `cpuColor` | hex color | `#007AFF` | CPU graph color |
| `memoryColor` | hex color | `#34C759` | Memory graph color |

### Behavior

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `autoHide` | bool | true | Auto-hide bar at top edge |
| `autoHideDwellTime` | number | 0.3 | Seconds before hiding |
| `autoHideFadeDuration` | number | 0.2 | Fade animation duration (s) |
| `launchAtLogin` | bool | false | Launch at system startup |

### Notifications

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `batteryLow` | bool | false | Enable low battery alert |
| `batteryThreshold` | number | 20.0 | Battery level (%) to trigger |
| `cpuHigh` | bool | false | Enable high CPU alert |
| `cpuThreshold` | number | 90.0 | CPU usage (%) to trigger |
| `cpuSustainedDuration` | number | 5.0 | Seconds above threshold before alert |
| `memoryHigh` | bool | false | Enable high memory alert |
| `memoryThreshold` | number | 90.0 | Memory usage (%) to trigger |
| `memorySustainedDuration` | number | 5.0 | Seconds above threshold before alert |

### Widget Layout

Each widget entry in the `widgets` array:

| Key | Type | Description |
|-----|------|-------------|
| `id` | string | Widget identifier (e.g. `"time"`, `"cpu"`, `"battery"`) |
| `section` | string | Position: `"left"`, `"center"`, or `"right"` |
| `sortIndex` | integer | Order within the section |
| `visible` | bool | Whether the widget is displayed |

<details>
<summary>Example config</summary>

```yaml
bar:
  height: 40
  cornerRadius: 12
  margin: 8
  yOffset: 4

appearance:
  accent: "#007AFF"
  barTint: "#000000"
  barTintOpacity: 0.0
  shadowEnabled: true

behavior:
  autoHide: true
  autoHideDwellTime: 0.3
  launchAtLogin: false

widgets:
  - id: apple-menu
    section: left
    sortIndex: 0
    visible: true
  - id: front-app
    section: left
    sortIndex: 1
    visible: true
  - id: time
    section: right
    sortIndex: 0
    visible: true
  - id: battery
    section: right
    sortIndex: 1
    visible: true
```

</details>

## Built-in Widgets

| Widget | Description | Update |
|--------|-------------|--------|
| Apple Menu | System actions & preferences | Event |
| Front App | Currently focused application | Event |
| CPU Graph | Real-time CPU usage mini-graph | 2s |
| Memory Graph | RAM usage mini-graph | 2s |
| Network | Upload / download speeds | 2s |
| Battery | Charge level & charging state | 60s |
| Volume | Volume level with popup control | Event |
| Bluetooth | Connected device count | 5s |
| Disk Usage | Disk utilization percentage | 30s |
| Mic / Camera | Active mic/camera indicator | Event |
| Input Source | Keyboard input source | Event |
| Time | Clock (customizable format) | 2s |
| Date | Date & calendar events | Event |
| Focus Timer | Pomodoro-style timer | Event |
| Chevron | Section separator | — |

## Plugins

StatusBar supports third-party plugins distributed as `.statusplugin.zip` archives via GitHub Releases. Install and manage plugins entirely through the Preferences UI — no CLI required.

## Install

```bash
brew tap hytfjwr/statusbar
brew install statusbar
```

Alternatively, download the `.app` bundle from [GitHub Releases](https://github.com/hytfjwr/StatusBar/releases).

## License

[MIT](LICENSE)
