// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clawake",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: the decision function, thermal hysteresis, config, battery
        // parsing. No AppKit/SwiftUI — the boundary is compiler-enforced, and it is
        // unit-testable headlessly.
        .target(
            name: "ClawakeCore",
            path: "Sources/ClawakeCore"
        ),
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
            dependencies: ["ClawakeCore", "ClawakeShared"],
            path: "Sources/Clawake"
        ),
        // Unit tests for the pure-logic core.
        .testTarget(
            name: "ClawakeCoreTests",
            dependencies: ["ClawakeCore"],
            path: "Tests/ClawakeCoreTests"
        ),
    ]
)
