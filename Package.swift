// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PortBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PortBar", path: "Sources/PortBar"),
    ]
)
