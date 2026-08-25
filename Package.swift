// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clawake",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clawake",
            path: "Sources/Clawake"
        )
    ]
)
