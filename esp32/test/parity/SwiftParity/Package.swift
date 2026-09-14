// swift-tools-version: 5.9
// The Swift half of the parity harness. Builds the REAL CodeCore engine and
// prints the same trace scenario.c prints, so the two can be diffed.
// Test-only: nothing in the watch or phone app depends on this.

import PackageDescription

let package = Package(
    name: "parity",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../../../CodeCore")],
    targets: [
        .executableTarget(
            name: "parity",
            dependencies: [.product(name: "CodeCore", package: "CodeCore")],
            path: "Sources/parity"
        )
    ]
)
