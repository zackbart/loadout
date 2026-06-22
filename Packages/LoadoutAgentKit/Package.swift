// swift-tools-version:6.2
import PackageDescription

// LoadoutAgentKit hosts the Loadout-specific agent plumbing:
//   - LocalSocketTransport: an AF_UNIX HerdrTransport to the live local Herdr.
//   - AgentContentKit: transcript resolution + structured block parsing.
// Both are filled in by later tasks; this scaffold only provides compiling stubs.
let package = Package(
    name: "LoadoutAgentKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "LocalSocketTransport", targets: ["LocalSocketTransport"]),
        .library(name: "AgentContentKit", targets: ["AgentContentKit"]),
    ],
    dependencies: [
        .package(path: "../HerdrKit"),
    ],
    targets: [
        .target(
            name: "LocalSocketTransport",
            dependencies: [
                .product(name: "HerdrKit", package: "HerdrKit"),
            ]
        ),
        .target(name: "AgentContentKit"),
        .testTarget(name: "AgentContentKitTests", dependencies: ["AgentContentKit"]),
    ],
    swiftLanguageModes: [.v5]
)
