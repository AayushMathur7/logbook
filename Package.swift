// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Logbook",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "LogbookCore", targets: ["LogbookCore"]),
        .executable(name: "LogbookApp", targets: ["LogbookApp"]),
        .executable(name: "logbook", targets: ["logbook"]),
        .executable(name: "logbook-selftest", targets: ["logbook-selftest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/appstefan/highlightswift.git", exact: "1.0.5"),
        .package(url: "https://github.com/exyte/SVGView.git", exact: "1.0.6"),
    ],
    targets: [
        .target(
            name: "LogbookCore",
            path: "Sources/LogbookCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "LogbookApp",
            dependencies: [
                "LogbookCore",
                .product(name: "HighlightSwift", package: "highlightswift"),
                .product(name: "SVGView", package: "SVGView"),
            ],
            path: "Sources/LogbookApp",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "logbook",
            dependencies: ["LogbookCore"],
            path: "Sources/logbook"
        ),
        .executableTarget(
            name: "logbook-selftest",
            dependencies: ["LogbookCore"],
            path: "Sources/logbookselftest"
        ),
    ]
)
