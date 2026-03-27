// swift-tools-version: 6.2

import PackageDescription

let swiftLint: Target.PluginUsage = .plugin(
    name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"
)

let package = Package(
    name: "StatusBar",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/hytfjwr/StatusBarKit", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.1"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "StatusBar",
            dependencies: [
                .product(name: "StatusBarKit", package: "StatusBarKit"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/StatusBar",

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
        .executableTarget(
            name: "sbar",
            dependencies: [
                .product(name: "StatusBarIPC", package: "StatusBarKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/statusbar-cli"
        ),
        .testTarget(
            name: "StatusBarTests",
            dependencies: [
                "StatusBar",
                .product(name: "StatusBarKit", package: "StatusBarKit"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Tests/StatusBarTests"
        ),
        .testTarget(
            name: "statusbar-cliTests",
            dependencies: ["sbar"],
            path: "Tests/statusbar-cliTests"
        ),
    ]
)
