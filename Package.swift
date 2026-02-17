// swift-tools-version: 5.9
// Moat Phase 0 PoC
// The MoatCore library and tests build via SPM.
// The host app (Moat) and system extension (MoatFilter) require Xcode.

import PackageDescription

let package = Package(
    name: "Moat",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MoatCore", targets: ["MoatCore"]),
    ],
    targets: [
        .target(
            name: "MoatCore",
            path: "MoatCore"
        ),
        .testTarget(
            name: "MoatTests",
            dependencies: ["MoatCore"],
            path: "MoatTests"
        ),
    ]
)
