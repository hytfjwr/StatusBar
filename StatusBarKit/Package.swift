// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StatusBarKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "StatusBarKit", type: .dynamic, targets: ["StatusBarKit"]),
    ],
    targets: [
        .target(
            name: "StatusBarKit",
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .unsafeFlags(["-Xlinker", "-install_name", "-Xlinker", "@rpath/libStatusBarKit.dylib"]),
            ]
        ),
    ]
)
