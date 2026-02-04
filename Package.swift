// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PRMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PRMonitor", targets: ["PRMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "PRMonitor",
            path: "Sources/PRMonitor"
        )
    ]
)
