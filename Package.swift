// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clawake",
    platforms: [.macOS(.v13)],
    targets: [
        // Shared XPC protocol + constants, compiled into both the app and the daemon.
        .target(
            name: "ClawakeShared",
            path: "Sources/ClawakeShared"
        ),
        // The privileged root daemon (installed via SMAppService, talks XPC).
        .executableTarget(
            name: "ClawakeHelper",
            dependencies: ["ClawakeShared"],
            path: "Sources/ClawakeHelper"
        ),
        // The menu bar app.
        .executableTarget(
            name: "Clawake",
            dependencies: ["ClawakeShared"],
            path: "Sources/Clawake"
        ),
    ]
)
