// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowLocal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FlowLocal", path: "Sources/FlowLocal"),
    ]
)
