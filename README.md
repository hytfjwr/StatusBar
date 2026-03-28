# StatusBar

<img width="1803" height="51" alt="image" src="https://github.com/user-attachments/assets/17ff03fd-3c4f-4493-8d73-3fed147de346" />

https://github.com/user-attachments/assets/ff474554-a8e3-4ccc-91ff-edb0f0bb1ed2

> A Swift-native custom status bar for macOS, inspired by [sketchybar](https://github.com/FelixKratz/SketchyBar).

[![CI](https://github.com/hytfjwr/StatusBar/actions/workflows/ci.yml/badge.svg)](https://github.com/hytfjwr/StatusBar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/hytfjwr/StatusBar?logo=github)](https://github.com/hytfjwr/StatusBar/releases/latest)
[![Homebrew](https://img.shields.io/badge/Homebrew-hytfjwr/statusbar-FBB040?logo=homebrew&logoColor=white)](https://github.com/hytfjwr/homebrew-statusbar)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26+-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Requirements

- **macOS 26** or later
- **Xcode 26** or later ([download](https://developer.apple.com/download/)) — only for building from source

## Installation

### Homebrew (recommended)

```bash
brew tap hytfjwr/statusbar
brew install --cask statusbar
```

### Build from Source

```bash
git clone https://github.com/hytfjwr/StatusBar.git
cd StatusBar
make run-dev   # Debug build
make run-app   # Release build
```

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

<img width="722" height="673" alt="Plugin Management UI" src="https://github.com/user-attachments/assets/9eed1e64-fda5-48d9-88a6-03f885442770" />

### Official Plugins

| Plugin | Description | Update |
|--------|-------------|--------|
| [AeroSpace](https://github.com/hytfjwr/statusbar-plugin-aerospace) | Tiling window manager workspace indicator | Event |
| [Spotify](https://github.com/hytfjwr/statusbar-plugin-spotify) | Now playing track title & artist | Event |
| [Docker](https://github.com/hytfjwr/statusbar-plugin-docker) | Running container count | 10s |
| [VPN](https://github.com/hytfjwr/statusbar-plugin-vpn) | VPN connection status | 5s |
| [Claude](https://github.com/hytfjwr/statusbar-plugin-claude) | Claude API usage & status | Event |

Install from Preferences > Plugins > Add Plugin using `hytfjwr/<plugin-name>`.

### Create Your Own

Use the [plugin template](https://github.com/hytfjwr/statusbar-plugin-template) to get started.

## Configuration

A default config is generated at `~/.config/statusbar/config.yml` on first launch. The file is hot-reloaded — edits are applied instantly without restarting. All settings are also available through the Preferences window (Apple Menu > Preferences).

<details>
<summary>Bar</summary>

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `height` | number | 40 | Bar height in pixels |
| `cornerRadius` | number | 12 | Corner radius in pixels |
| `margin` | number | 8 | Margin from screen edges |
| `yOffset` | number | 4 | Vertical offset from top |
| `widgetSpacing` | number | 6 | Space between widgets |
| `widgetPaddingH` | number | 6 | Horizontal padding inside each widget |

</details>

<details>
<summary>Appearance</summary>

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

</details>

<details>
<summary>Typography</summary>

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `iconFontSize` | number | 13 | Icon font size (pt) |
| `labelFontSize` | number | 13 | Label font size (pt) |
| `smallFontSize` | number | 11 | Small text font size (pt) |
| `monoFontSize` | number | 12 | Monospace font size (pt) |

</details>

<details>
<summary>Graphs</summary>

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `width` | number | 30 | Graph width in pixels |
| `height` | number | 14 | Graph height in pixels |
| `dataPoints` | integer | 50 | Number of data points to display |
| `cpuColor` | hex color | `#007AFF` | CPU graph color |
| `memoryColor` | hex color | `#34C759` | Memory graph color |

</details>

<details>
<summary>Behavior</summary>

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `autoHide` | bool | true | Auto-hide bar at top edge |
| `autoHideDwellTime` | number | 0.3 | Seconds before hiding |
| `autoHideFadeDuration` | number | 0.2 | Fade animation duration (s) |
| `launchAtLogin` | bool | false | Launch at system startup |

</details>

<details>
<summary>Notifications</summary>

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

</details>

<details>
<summary>Widget Layout</summary>

Each widget entry in the `widgets` array:

| Key | Type | Description |
|-----|------|-------------|
| `id` | string | Widget identifier (e.g. `"time"`, `"cpu"`, `"battery"`) |
| `section` | string | Position: `"left"`, `"center"`, or `"right"` |
| `sortIndex` | integer | Order within the section |
| `visible` | bool | Whether the widget is displayed |

</details>

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

## CLI (`sbar`)

StatusBar includes a command-line tool `sbar` for controlling the app from the terminal or scripts. It communicates with the running app via Unix domain socket.

When installed via Homebrew, `sbar` is automatically available on your PATH. For development builds, run `make install-cli`.

### Commands

```bash
# List all widgets
sbar list
sbar list --json

# Get widget details
sbar get battery
sbar get cpu-graph --json

# Set widget settings
sbar set battery showPercentage=true
sbar set cpu-graph visible=false
sbar set time format="HH:mm:ss"

# Set global preferences
sbar set --global bar.height=44
sbar set --global appearance.accent=#FF0000
sbar set --global behavior.autoHide=false

# Send custom events to plugin widgets
sbar trigger com.example.myapp.deploy_finished
sbar trigger com.example.myapp.count --payload 42
sbar trigger com.example.myapp.deploy --payload '{"repo":"myapp","status":"ok"}'

# Subscribe to real-time events (NDJSON stream)
sbar subscribe front_app_switched volume_changed config_reloaded

# Wildcard: subscribe to all battery events
sbar subscribe 'battery_*'

# Subscribe to all events
sbar subscribe '*'

# Pipe events to jq for filtering
sbar subscribe front_app_switched | jq '.payload'

# Toast notifications
sbar toast --title "Deploy done" --message "v1.2.3 shipped" --level success
sbar toast --title "CPU Warning" --level warning --duration 10
sbar toast --title "Error" --level error --action-label "Open Logs" --action "open /var/log"

# Relaunch the app
sbar reload
```

Use `--json` for machine-readable output (pipe to `jq` for filtering).

<details>
<summary>Event subscription</summary>

`sbar subscribe` keeps the connection open and streams events as newline-delimited JSON (NDJSON) to stdout. Supports wildcard patterns — a name ending in `*` matches any event with that prefix (e.g., `battery_*` matches `battery_changed`, `battery_charging_changed`, `battery_low`).

**Raw events** (emitted on every value change):

| Event | Payload | Source |
|-------|---------|--------|
| `battery_changed` | `percent`, `charging`, `hasBattery` | Battery widget |
| `cpu_updated` | `percent` | CPU graph widget |
| `memory_updated` | `percent` | Memory graph widget |
| `network_updated` | `downloadBytesPerSec`, `uploadBytesPerSec` | Network widget |
| `disk_updated` | `usedPercent`, `usedBytes`, `totalBytes` | Disk widget |
| `volume_changed` | `volume`, `muted` | Volume widget |
| `mic_camera_changed` | `micActive`, `cameraActive` | Mic/Camera widget |

**State transition events** (emitted on discrete state changes):

| Event | Payload | Trigger |
|-------|---------|---------|
| `front_app_switched` | `appName`, `bundleID` | Active app changes |
| `battery_charging_changed` | `charging` | Charger plugged/unplugged |
| `input_source_changed` | `abbreviation` | Keyboard source switched |
| `volume_muted` | — | Audio muted |
| `volume_unmuted` | — | Audio unmuted |
| `mic_activated` / `mic_deactivated` | — | Microphone starts/stops |
| `camera_activated` / `camera_deactivated` | — | Camera starts/stops |
| `bluetooth_devices_changed` | `connectedCount`, `deviceNames` | Device list changes |
| `bluetooth_device_connected` | `name`, `category` | New device connected |
| `bluetooth_device_disconnected` | `name` | Device disconnected |
| `focus_timer_started` | `mode`, `durationSeconds` | Timer started |
| `focus_timer_stopped` | — | Timer cancelled |
| `focus_timer_completed` | `mode` | Timer finished |
| `calendar_next_event_changed` | `title`, `startDate`, `timeUntilStartSeconds` | Next event changes |

**Threshold events** (emitted when crossing configured boundaries):

| Event | Payload | Trigger |
|-------|---------|---------|
| `battery_low` | `percent`, `threshold` | Battery drops below threshold |
| `cpu_high` | `usagePercent`, `threshold`, `sustainedSeconds` | CPU sustained above threshold |
| `memory_high` | `usagePercent`, `threshold`, `sustainedSeconds` | Memory sustained above threshold |
| `disk_high` | `usedPercent`, `threshold` | Disk crosses 80% or 90% |

**Infrastructure events:**

| Event | Trigger |
|-------|---------|
| `config_reloaded` | Config file hot-reloaded from disk |

Each line is a JSON object:

```json
{"event":"front_app_switched","timestamp":1711411234.56,"payload":{"appName":"Safari","bundleID":"com.apple.Safari"}}
```

Examples:

```bash
# React to focus timer completion
sbar subscribe focus_timer_completed | while read -r line; do
  osascript -e 'display notification "Break time!" with title "Focus Timer"'
done

# Log all battery events
sbar subscribe 'battery_*' | jq -c '{event, payload}'

# Monitor privacy indicators
sbar subscribe mic_activated mic_deactivated camera_activated camera_deactivated
```

The stream ends when the app quits or the connection is interrupted (Ctrl-C).

</details>

<details>
<summary>Trigger events</summary>

`sbar trigger` sends custom events to plugin widgets that have subscribed to them via `subscribedEvents`. Plugins receive events through the `handleEvent(_:)` callback.

```bash
sbar trigger <event> [--payload <value>]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<event>` | Yes | Fully-qualified event name (e.g. `com.example.myapp.deploy_finished`) |
| `--payload` | No | Event payload — parsed as JSON if valid, otherwise treated as a plain string |

Payload examples:

```bash
sbar trigger com.example.myapp.ping                              # no payload
sbar trigger com.example.myapp.count --payload 42                # number
sbar trigger com.example.myapp.status --payload "building"       # string
sbar trigger com.example.myapp.deploy --payload '{"status":"ok"}' # JSON object
```

</details>

<details>
<summary>Toast notifications</summary>

`sbar toast` displays a Liquid Glass notification panel below the bar. Toasts stack vertically (up to 4) and auto-dismiss after a configurable duration.

```bash
sbar toast --title <text> [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--title` | (required) | Toast title |
| `--message` | — | Body text |
| `--icon` | (per level) | SF Symbol name |
| `--level` | `info` | `info`, `success`, `warning`, `error` |
| `--duration` | `5` | Auto-dismiss seconds (`0` = persistent) |
| `--action-label` | — | Action button label |
| `--action` | — | Shell command on action click |

Returns the toast ID (UUID) on success.

Plugins can also post toasts via `ToastService.shared.post(request)`.

</details>

<details>
<summary>Global key paths</summary>

The `sbar set --global` command uses dot-separated key paths matching the YAML config structure:

| Category | Key paths |
|----------|-----------|
| Bar | `bar.height`, `bar.cornerRadius`, `bar.margin`, `bar.yOffset`, `bar.widgetSpacing`, `bar.widgetPaddingH` |
| Appearance | `appearance.accent`, `appearance.barTint`, `appearance.barTintOpacity`, `appearance.shadowEnabled`, `appearance.popupCornerRadius`, `appearance.popupPadding` |
| Typography | `typography.iconFontSize`, `typography.labelFontSize`, `typography.smallFontSize`, `typography.monoFontSize` |
| Graphs | `graphs.width`, `graphs.height`, `graphs.dataPoints`, `graphs.cpuColor`, `graphs.memoryColor` |
| Behavior | `behavior.autoHide`, `behavior.autoHideDwellTime`, `behavior.autoHideFadeDuration`, `behavior.launchAtLogin`, `behavior.hideInFullscreen` |
| Notifications | `notifications.batteryLow`, `notifications.batteryThreshold`, `notifications.cpuHigh`, `notifications.cpuThreshold`, `notifications.memoryHigh`, `notifications.memoryThreshold` |

</details>

## License

[MIT](LICENSE)
