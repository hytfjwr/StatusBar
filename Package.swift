// swift-tools-version: 6.2

import Foundation
import PackageDescription

// MARK: - Read plugins.json

struct PluginEntry: Decodable {
    let module: String
    let url: String?
    let from: String?
}

let pluginsFileURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("plugins.json")

let pluginEntries: [PluginEntry] = {
    guard let data = try? Data(contentsOf: pluginsFileURL) else { return [] }
    return (try? JSONDecoder().decode([PluginEntry].self, from: data)) ?? []
}()

let localPlugins = pluginEntries.filter { $0.url == nil }
let remotePlugins = pluginEntries.filter { $0.url != nil }

func inferPackageName(from url: String) -> String {
    URL(string: url)?
        .deletingPathExtension()
        .lastPathComponent ?? url
}

// MARK: - Package

let swiftLint: Target.PluginUsage = .plugin(
    name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"
)

let package = Package(
    name: "StatusBar",
    platforms: [.macOS(.v26)],
    products: localPlugins.map {
        .library(name: $0.module, targets: [$0.module])
    },
    dependencies: [
        .package(path: "StatusBarKit"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
    ] + remotePlugins.compactMap { entry in
        guard let url = entry.url else { return nil }
        return .package(url: url, from: .init(stringLiteral: entry.from ?? "1.0.0"))
    },
    targets: [
        // Executable
        .executableTarget(
            name: "StatusBar",
            dependencies: [
                    .product(name: "StatusBarKit", package: "StatusBarKit"),
                    .product(name: "Yams", package: "Yams"),
                ]
                + localPlugins.map { Target.Dependency.target(name: $0.module) }
                + remotePlugins.map {
                    Target.Dependency.product(
                        name: $0.module,
                        package: inferPackageName(from: $0.url!)
                    )
                },
            path: "Sources/StatusBar",
            exclude: ["../../Resources/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("EventKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ],
            plugins: [swiftLint]
        ),
    ]

    // Local plugin targets (auto-generated from plugins.json)
    + localPlugins.map { entry in
        .target(
            name: entry.module,
            dependencies: [
                .product(name: "StatusBarKit", package: "StatusBarKit"),
            ],
            path: "Sources/Plugins/\(entry.module)",
            plugins: [swiftLint]
        )
    }
)
