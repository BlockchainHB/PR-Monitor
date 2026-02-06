// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PRMonitor", targets: ["PRMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "PRMonitor",
            path: "Sources/PRMonitor"
        ),
        .testTarget(
            name: "PRMonitorTests",
            dependencies: ["PRMonitor"],
            path: "Tests/PRMonitorTests"
        )
    ]
)
