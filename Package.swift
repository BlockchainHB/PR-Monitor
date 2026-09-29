// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PRMonitor",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PRMonitor", targets: ["PRMonitor"]),
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
        ),
    ],
    swiftLanguageModes: [.v6]
)
