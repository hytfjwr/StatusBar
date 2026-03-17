# Plugin Architecture — dylib 動的ロード方式

## 概要

サードパーティ開発者が Swift で StatusBarKit プロトコルに準拠したプラグインを開発し、
ビルド済み `.dylib` として GitHub Releases に公開する。
エンドユーザーは設定画面 (Preferences) から GitHub URL を入力するだけでプラグインをインストールできる。
Swift ツールチェーンは不要。

## 設計方針

- **Library Evolution Mode**: StatusBarKit を `-enable-library-evolution` でビルドし、マイナーバージョン間の ABI 互換性を保証
- **セマンティックバージョニング**: メジャーバージョン一致でプラグインをロード (1.x.x 同士なら互換)
- **dlopen 前検証**: manifest のバージョン情報で互換性を検証し、非互換プラグインはロードしない (クラッシュ防止)
- **GUI 統合**: プラグイン管理は Preferences ウィンドウ内で完結 (CLI ツール不要)

---

## 1. StatusBarKit 動的フレームワーク化

### パッケージ構成 (実装済み)

StatusBarKit は独立した Swift パッケージとして分離済み:

```
macos-status-bar/
├── StatusBarKit/                    # 独立パッケージ
│   ├── Package.swift
│   └── Sources/StatusBarKit/
├── Package.swift                    # メインアプリ (StatusBarKit をローカル依存)
└── Sources/StatusBar/
```

メイン Package.swift での依存:
```swift
.package(path: "StatusBarKit"),
// ...
.product(name: "StatusBarKit", package: "StatusBarKit"),  // 動的リンク
```

StatusBarKit/Package.swift:

```swift
.library(name: "StatusBarKit", type: .dynamic, targets: ["StatusBarKit"])
```

```swift
.target(
    name: "StatusBarKit",
    swiftSettings: [
        .unsafeFlags(["-enable-library-evolution"]),
    ],
    linkerSettings: [
        .linkedFramework("AppKit"),
        .unsafeFlags(["-install_name", "@rpath/libStatusBarKit.dylib"]),
    ]
)
```

実行ファイルに `@rpath` を設定:

```swift
.executableTarget(
    name: "StatusBar",
    // ...
    linkerSettings: [
        // ...existing frameworks...
        .unsafeFlags([
            "-rpath", "@executable_path",                // SPM debug 用
            "-rpath", "@executable_path/../Frameworks",  // .app バンドル用
        ]),
    ]
)
```

### .app バンドル構造

```
StatusBar.app/
  Contents/
    MacOS/
      StatusBar                          # メインバイナリ
    Frameworks/
      libStatusBarKit.dylib              # 共有動的フレームワーク
    Resources/
      Info.plist
    _CodeSignature/
```

プラグインの `.dylib` はこの共有フレームワーク経由でプロトコル型を解決する。
StatusBarKit が静的リンクだと型の同一性が崩れるため、動的フレームワークが必須。

---

## 2. プラグインバンドル形式

### ディレクトリ構造

```
~/.config/statusbar/
├── config.yml
├── plugins/
│   ├── registry.json                        # インストール済みプラグイン一覧
│   ├── com.example.weather.statusplugin/     # プラグインバンドル
│   │   ├── manifest.json
│   │   └── libWeatherPlugin.dylib
│   └── com.example.pomodoro.statusplugin/
│       ├── manifest.json
│       └── libPomodoroPlugin.dylib
```

### manifest.json スキーマ

```json
{
  "id": "com.example.weather",
  "name": "Weather Widget",
  "version": "1.0.0",
  "statusBarKitVersion": "1.2.0",
  "swiftVersion": "6.2",
  "entrySymbol": "createStatusBarPlugin",
  "description": "Weather widget with forecast",
  "author": "Author Name",
  "homepage": "https://github.com/user/sb-weather",
  "sha256": "a1b2c3..."
}
```

| フィールド | 必須 | 用途 |
|-----------|------|------|
| `id` | Yes | 一意識別子 (reverse-domain) |
| `name` | Yes | 表示名 |
| `version` | Yes | プラグインバージョン (semver) |
| `statusBarKitVersion` | Yes | ビルド時の StatusBarKit バージョン |
| `swiftVersion` | Yes | ビルド時の Swift コンパイラバージョン |
| `entrySymbol` | Yes | `dlsym` で検索する C シンボル名 |
| `description` | No | 説明文 |
| `author` | No | 作者名 |
| `homepage` | No | GitHub URL 等 |
| `sha256` | No | dylib の SHA-256 チェックサム (改竄検知) |

---

## 3. バージョン互換性戦略

### Library Evolution Mode による ABI 安定化

`-enable-library-evolution` を有効にすると:

1. **構造体のメモリレイアウトが間接参照になる** → フィールド追加してもプラグイン側は壊れない
2. **プロトコル witness table が安定メタデータ経由** → プロトコル要件追加 (デフォルト実装付き) でも互換
3. **`.swiftinterface` ファイル生成** → テキストベースの安定インターフェース

### バージョン検証ロジック

```
プラグインの statusBarKitVersion: 1.2.0
アプリの StatusBarKit バージョン:  1.5.0

→ メジャーバージョン一致 (1 == 1) → ロード許可
→ プラグインの minorVersion ≤ アプリの minorVersion (2 ≤ 5) → OK
```

```
プラグインの statusBarKitVersion: 2.0.0
アプリの StatusBarKit バージョン:  1.5.0

→ メジャーバージョン不一致 (2 ≠ 1) → ロード拒否
→ UI に「プラグイン X は StatusBar v2.x が必要です」と表示
```

#### 互換性マトリクス

| アプリ StatusBarKit | プラグイン要求 | 結果 |
|--------------------|---------------|------|
| 1.5.0 | 1.0.0 | ✅ ロード (後方互換) |
| 1.5.0 | 1.5.0 | ✅ ロード (完全一致) |
| 1.5.0 | 1.6.0 | ❌ 拒否 (プラグインが新しいAPIを要求する可能性) |
| 1.5.0 | 2.0.0 | ❌ 拒否 (メジャーバージョン不一致) |
| 2.0.0 | 1.5.0 | ❌ 拒否 (メジャーバージョン不一致) |

### StatusBarKit API ルール

| 操作 | バージョンへの影響 | 古いプラグイン |
|------|-------------------|--------------|
| メソッド/型の追加 | マイナーバージョン UP | ✅ 動く |
| デフォルト実装付きプロトコル要件追加 | マイナーバージョン UP | ✅ 動く |
| 既存 API の削除・変更 | **メジャーバージョン UP** | ❌ 再ビルド必要 |
| バグ修正のみ | パッチバージョン UP | ✅ 動く |

### CI での ABI 検証

リリース時に `swift-api-digester` で前バージョンとの ABI 差分を検出:

```bash
swift api-digester -diagnose-sdk \
  -baseline-path old-StatusBarKit.swiftinterface \
  --input-paths new-StatusBarKit.swiftinterface
```

API 削除が検出されたらメジャーバージョンアップを強制。

---

## 4. プラグインエントリポイント

### @MainActor と @_cdecl の衝突問題

`@_cdecl` 関数は `nonisolated`。`StatusBarPlugin` は `@MainActor`。
直接インスタンス化すると Swift 6 コンパイラがエラーを出す。

### 解決: PluginBox パターン

**StatusBarKit 側** (新規ファイル: `PluginBox.swift`):

```swift
/// プラグイン dylib のエントリポイントから返される型。
/// nonisolated コンテキスト (C関数) から @MainActor プラグインを安全に生成するためのブリッジ。
public final class PluginBox: @unchecked Sendable {
    public let factory: @MainActor () -> any StatusBarPlugin

    public init(_ factory: @escaping @MainActor () -> any StatusBarPlugin) {
        self.factory = factory
    }
}
```

**プラグイン側**:

```swift
import StatusBarKit

@MainActor
public final class WeatherPlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.example.weather",
        name: "Weather Widget",
        version: "1.0.0"
    )
    public let widgets: [any StatusBarWidget]
    public init() { widgets = [WeatherWidget()] }
}

// C 呼び出し可能なファクトリ関数 (nonisolated)
@_cdecl("createStatusBarPlugin")
public func createStatusBarPlugin() -> UnsafeMutableRawPointer {
    let box = PluginBox { WeatherPlugin() }
    return Unmanaged.passRetained(box).toOpaque()
}
```

**ホスト側 (DylibPluginLoader)**:

```swift
// @MainActor コンテキストで実行
let box = Unmanaged<PluginBox>.fromOpaque(rawPtr).takeRetainedValue()
let plugin = box.factory()  // @MainActor クロージャを安全に実行
registry.registerPlugin(plugin)
```

---

## 5. DylibPluginLoader 設計

```swift
@MainActor
public final class DylibPluginLoader {
    static let shared = DylibPluginLoader()

    private var loadedHandles: [String: UnsafeMutableRawPointer] = [:]  // plugin id → dlhandle
    private var loadedPlugins: [String: any StatusBarPlugin] = [:]

    /// 全プラグインをスキャンしてロード
    func loadAll(into registry: any WidgetRegistryProtocol) {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/statusbar/plugins")
        // *.statusplugin ディレクトリをスキャン
        // 各バンドルに対して load(bundleURL:into:) を呼ぶ
    }

    /// 単一プラグインバンドルをロード
    func load(bundleURL: URL, into registry: any WidgetRegistryProtocol) throws {
        // 1. manifest.json パース
        // 2. statusBarKitVersion 互換性チェック (セマンティックバージョニング)
        // 3. dlopen(dylibPath, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST)
        // 4. dlsym(handle, entrySymbol)
        // 5. unsafeBitCast → (@convention(c) () -> UnsafeMutableRawPointer)
        // 6. factory() → PluginBox → plugin
        // 7. plugin.register(to: registry)
        // 8. loadedHandles / loadedPlugins に保持
    }

    /// プラグインをアンロード (次回再起動で完全除去)
    func markForRemoval(pluginID: String) {
        // loadedPlugins から widgets を stop()
        // 実際の dlclose は再起動時 (Swift ARC の制約)
    }
}
```

### PluginLoadError

```swift
enum PluginLoadError: Error, LocalizedError {
    case manifestNotFound(URL)
    case manifestDecodingFailed(URL, Error)
    case incompatibleStatusBarKitVersion(required: String, current: String)
    case dylibNotFound(URL)
    case dlopenFailed(String)       // dlerror() メッセージ
    case symbolNotFound(String)
    case pluginBoxCastFailed
    case pluginFactoryFailed
}
```

### dlopen フラグ

| フラグ | 理由 |
|--------|------|
| `RTLD_NOW` | 未解決シンボルをロード時に検出 (遅延ではなく即座にエラー) |
| `RTLD_LOCAL` | プラグインのシンボルがグローバル名前空間を汚染しない |
| `RTLD_FIRST` | (macOS 固有) シンボル検索を dylib とその直接依存に限定 |

---

## 6. プラグインインストールフロー (GUI)

### Preferences → Plugins セクション

```
┌─────────────────────────────────────────────────┐
│  Plugins                                         │
├─────────────────────────────────────────────────┤
│                                                   │
│  Installed:                                       │
│  ┌───────────────────────────────────────────┐   │
│  │ 🌤 Weather Widget  v1.0.0   [Disable][🗑]│   │
│  │ 🍅 Pomodoro Timer  v2.1.0   [Disable][🗑]│   │
│  └───────────────────────────────────────────┘   │
│                                                   │
│  Add Plugin:                                      │
│  ┌──────────────────────────────────┐ [Install]  │
│  │ https://github.com/user/sb-xxx  │             │
│  └──────────────────────────────────┘             │
│                                                   │
│  ⚠ Plugins run with full app permissions.        │
│    Only install plugins from trusted sources.     │
│                                                   │
└─────────────────────────────────────────────────┘
```

### インストールフロー

```
1. ユーザーが GitHub URL を入力して [Install] クリック
2. GitHubPluginInstaller:
   a. URL から owner/repo を抽出
   b. GET https://api.github.com/repos/{owner}/{repo}/releases/latest
   c. assets から *.statusplugin.zip を検出
   d. ダウンロード → /tmp/ に展開
   e. manifest.json を検証 (statusBarKitVersion 互換性チェック)
   f. ~/.config/statusbar/plugins/{id}.statusplugin/ にコピー
   g. registry.json を更新
3. アプリ再起動プロンプトを表示
4. 再起動後、DylibPluginLoader が自動でロード
```

### registry.json スキーマ

```json
{
  "plugins": [
    {
      "id": "com.example.weather",
      "name": "Weather Widget",
      "version": "1.0.0",
      "githubURL": "https://github.com/user/sb-weather",
      "installedAt": "2026-03-17T10:00:00Z",
      "enabled": true
    }
  ]
}
```

---

## 7. メモリ管理

### 重要な順序

```
アンロード時:
1. plugin.widgets.forEach { $0.stop() }    ← ウィジェット停止
2. loadedPlugins[id] = nil                 ← ARC でプラグインオブジェクト解放
3. dlclose(handle)                         ← dylib アンマップ
```

**`dlclose` は `loadedPlugins` からの参照解放後に呼ぶ。**
逆にすると、オブジェクトのデアロケーターが unmap 済みコードを実行してクラッシュ。

### ホットアンロードの制限

Swift ARC の制約により、完全なホットアンロードは安全ではない。
プラグインの `@Observable` 状態が SwiftUI クロージャにキャプチャされている可能性があるため、
**プラグイン削除は「次回再起動で除去」として処理する。**

---

## 8. セキュリティ

### リスク

dylib ロードは任意コード実行と等価。プラグインはアプリプロセス内で全権限を持つ。

### 緩和策

1. **コード署名検証** (将来実装): `SecStaticCodeCreateWithPath` で dylib の署名を検証
2. **SHA-256 チェックサム**: manifest に記録し、ロード前に照合 (改竄検知)
3. **UI での警告**: インストール時に「信頼できるソースからのみインストールしてください」を表示
4. **Entitlements**: `com.apple.security.cs.disable-library-validation` が必要

### Entitlements ファイル (StatusBar.entitlements)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

### App Sandbox 非互換

`dlopen` はサンドボックス外パスに対して使えないため、Mac App Store 配布は不可。
将来 MAS 配布が必要な場合は XPC ベースのプラグインアーキテクチャが必要。

---

## 9. Homebrew Cask 配布

### Tap リポジトリ (homebrew-statusbar)

```ruby
cask "statusbar" do
  version "1.0.0"
  sha256 "..."
  url "https://github.com/{user}/macos-status-bar/releases/download/v#{version}/StatusBar.zip"
  name "StatusBar"
  desc "Custom macOS status bar built with SwiftUI"
  homepage "https://github.com/{user}/macos-status-bar"
  depends_on macos: ">= :tahoe"

  app "StatusBar.app"
end
```

ユーザー:
```bash
brew tap {user}/statusbar
brew install --cask statusbar
```

### GitHub Actions リリースワークフロー

```yaml
# .github/workflows/release.yml
on:
  push:
    tags: ["v*"]

jobs:
  build:
    runs-on: macos-15  # Xcode 26 対応ランナーが利用可能になり次第変更
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: make release
      - name: Create .app bundle
        run: make bundle
      - name: Ad-hoc sign
        run: codesign --force --deep -s - StatusBar.app
      - name: Package
        run: zip -r StatusBar.zip StatusBar.app
      - name: Upload Release
        uses: softprops/action-gh-release@v2
        with:
          files: StatusBar.zip
```

### Developer ID なしの制約

- Notarization 不可
- ユーザーは初回起動時に Gatekeeper 警告を手動許可
- `xattr -d com.apple.quarantine /Applications/StatusBar.app` が必要な場合あり
- Cask に `caveats` で手順を記載

---

## 10. Makefile 拡張

```makefile
APP_NAME = StatusBar
APP_BUNDLE = $(APP_NAME).app
STATUSBARKIT_DYLIB = libStatusBarKit.dylib

bundle: release
	@echo "Creating $(APP_BUNDLE)..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp .build/release/$(STATUSBARKIT_DYLIB) $(APP_BUNDLE)/Contents/Frameworks/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@echo "Done: $(APP_BUNDLE)"

sign: bundle
	codesign --force --deep -s - $(APP_BUNDLE)

package: sign
	zip -r $(APP_NAME).zip $(APP_BUNDLE)
```

---

## 11. プラグイン開発者向け SDK

### テンプレートリポジトリ構造

```
statusbar-plugin-template/
├── Package.swift
├── Sources/
│   └── MyPlugin/
│       ├── MyPlugin.swift        # StatusBarPlugin 準拠 + @_cdecl ファクトリ
│       └── MyWidget.swift        # StatusBarWidget 準拠
├── .github/
│   └── workflows/
│       └── build.yml             # .statusplugin ビルド + Releases アップロード
├── Scripts/
│   └── package-plugin.sh         # .statusplugin バンドル作成スクリプト
└── README.md
```

### テンプレート Package.swift

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
        .package(url: "https://github.com/{user}/macos-status-bar", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MyPlugin",
            dependencies: [
                .product(name: "StatusBarKit", package: "macos-status-bar"),
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
            ]
        ),
    ]
)
```

### プラグインビルド → .statusplugin 作成

```bash
#!/bin/bash
# Scripts/package-plugin.sh
PLUGIN_NAME="MyPlugin"

swift build -c release
mkdir -p "${PLUGIN_NAME}.statusplugin"
cp ".build/release/lib${PLUGIN_NAME}.dylib" "${PLUGIN_NAME}.statusplugin/"
cp manifest.json "${PLUGIN_NAME}.statusplugin/"
zip -r "${PLUGIN_NAME}.statusplugin.zip" "${PLUGIN_NAME}.statusplugin"
```

---

## 12. 実装フェーズ

### Phase 1: StatusBarKit 動的化 (プラグインの土台)

- [ ] Package.swift: StatusBarKit を `.dynamic` + `-enable-library-evolution` に変更
- [ ] Package.swift: 実行ファイルに `@rpath` 設定
- [ ] StatusBarKit に `StatusBarKitVersion.swift` 追加 (バージョン定数)
- [ ] StatusBarKit に `PluginBox.swift` 追加
- [ ] Makefile: `bundle` ターゲットに Frameworks/ コピー追加
- [ ] ビルド確認: 既存機能が壊れないこと

### Phase 2: dylib プラグインローダー

- [ ] `StatusBarKit/DylibPluginManifest.swift` 作成
- [ ] `StatusBar/Plugins/DylibPluginLoader.swift` 作成
- [ ] `StatusBar/Plugins/PluginStore.swift` 作成 (registry.json 永続化)
- [ ] `AppDelegate.swift` に `DylibPluginLoader.loadAll()` 呼び出し追加
- [ ] `StatusBar.entitlements` 作成

### Phase 3: GUI プラグイン管理

- [ ] `StatusBar/Plugins/GitHubPluginInstaller.swift` 作成
- [ ] `StatusBar/Preferences/Sections/PluginsSection.swift` 作成
- [ ] `PreferencesView.swift` に `.plugins` セクション追加

### Phase 4: CI/CD + Homebrew

- [ ] `.github/workflows/release.yml` 作成
- [ ] `homebrew-statusbar` Tap リポジトリ作成
- [ ] Cask 定義作成

### Phase 5: プラグイン SDK

- [ ] プラグインテンプレートリポジトリ作成
- [ ] GitHub Actions テンプレート (プラグイン作者向け)
- [ ] ドキュメント作成
