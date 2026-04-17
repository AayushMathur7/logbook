// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Driftly",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "DriftlyCore", targets: ["DriftlyCore"]),
        .executable(name: "DriftlyApp", targets: ["DriftlyAppExec"]),
        .executable(name: "driftly", targets: ["driftly"]),
        .executable(name: "driftly-selftest", targets: ["driftly-selftest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/appstefan/highlightswift.git", exact: "1.0.5"),
        .package(url: "https://github.com/exyte/SVGView.git", exact: "1.0.6"),
    ],
    targets: [
        .target(
            name: "DriftlyCore",
            path: "Sources/DriftlyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "DriftlyApp",
            dependencies: [
                "DriftlyCore",
                .product(name: "HighlightSwift", package: "highlightswift"),
                .product(name: "SVGView", package: "SVGView"),
            ],
            path: "Sources/DriftlyApp",
            exclude: [
                "main.swift",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "DriftlyAppExec",
            dependencies: ["DriftlyApp"],
            path: "Sources/DriftlyAppExec"
        ),
        .executableTarget(
            name: "driftly",
            dependencies: ["DriftlyCore"],
            path: "Sources/driftly"
        ),
        .executableTarget(
            name: "driftly-selftest",
            dependencies: ["DriftlyCore", "DriftlyApp"],
            path: "Sources/driftlyselftest"
        ),
    ]
)
