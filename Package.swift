// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GRID",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (models, geometry, matching) — no AppKit, fully testable
        .target(
            name: "GRIDCore",
            path: "src/Core"
        ),
        // Menu bar agent
        .executableTarget(
            name: "GRID",
            dependencies: ["GRIDCore"],
            path: "src/App",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "GRIDCoreTests",
            dependencies: ["GRIDCore"],
            path: "Tests/GRIDCoreTests"
        ),
    ]
)
