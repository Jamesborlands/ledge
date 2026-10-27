// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Ledge", path: "Sources/Ledge")
    ],
    swiftLanguageModes: [.v5]
)
