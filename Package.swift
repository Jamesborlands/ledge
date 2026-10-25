// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Ledge", path: "Sources/Ledge")
    ]
)
