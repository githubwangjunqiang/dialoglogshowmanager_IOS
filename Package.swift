// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShowLog",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "ShowLog",
            targets: ["ShowLog"]
        )
    ],
    targets: [
        .target(
            name: "ShowLog",
            path: "Sources/ShowLog",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "ShowLogTests",
            dependencies: ["ShowLog"],
            path: "Tests/ShowLogTests"
        )
    ]
)
