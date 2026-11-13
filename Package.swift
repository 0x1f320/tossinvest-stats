// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TossBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TossBar",
            path: "Sources/TossBar"
        ),
        .testTarget(
            name: "TossBarTests",
            dependencies: ["TossBar"],
            path: "Tests/TossBarTests"
        ),
    ]
)
