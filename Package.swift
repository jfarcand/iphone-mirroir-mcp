// swift-tools-version: 6.0
// ABOUTME: Swift package manifest for the Mirroir MCP server.
// ABOUTME: Deployment target is macOS 14 for API availability; iPhone Mirroring requires macOS 15+ at runtime.

import PackageDescription

let package = Package(
    name: "mirroir-mcp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "HelperLib",
            path: "Sources/HelperLib",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("CoreText"),
            ]
        ),
        .executableTarget(
            name: "mirroir-mcp",
            dependencies: ["HelperLib"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("Vision"),
            ]
        ),
        .executableTarget(
            name: "mirroir-helper",
            dependencies: ["HelperLib"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .executableTarget(
            name: "FakeMirroring",
            path: "Sources/FakeMirroring",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "HelperLibTests",
            dependencies: ["HelperLib"]
        ),
        .testTarget(
            name: "MCPServerTests",
            dependencies: ["mirroir-mcp", "HelperLib"]
        ),
        .testTarget(
            name: "HelperDaemonTests",
            dependencies: ["mirroir-helper", "HelperLib"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["mirroir-mcp", "HelperLib"],
            linkerSettings: [
                .linkedFramework("Vision"),
            ]
        ),
        .testTarget(
            name: "TestRunnerTests",
            dependencies: ["mirroir-mcp", "HelperLib"]
        ),
    ]
)
