// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sortomat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sortomat",
            path: "Sources/Sortomat"
        )
    ]
)
