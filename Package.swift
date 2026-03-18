// swift-tools-version: 6.2

import PackageDescription

let swiftLint: Target.PluginUsage = .plugin(
    name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"
)

let package = Package(
    name: "StatusBar",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/hytfjwr/StatusBarKit", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
    ],
    targets: [
        .executableTarget(
            name: "StatusBar",
            dependencies: [
                .product(name: "StatusBarKit", package: "StatusBarKit"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/StatusBar",
            exclude: ["../../Resources/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
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
)
