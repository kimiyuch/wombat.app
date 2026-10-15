// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wombat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Wombat", path: "Sources/Wombat")
    ]
)
