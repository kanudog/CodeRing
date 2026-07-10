// swift-tools-version: 5.9
// CodeCore — shared logic for CodeRing (watchOS + iOS).
// All clinical math, models, storage, and sync live here so both apps
// import one tested module. DEMO PROJECT — not for clinical use.

import PackageDescription

let package = Package(
    name: "CodeCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)   // lets `swift test` run on the Mac; apps ignore this
    ],
    products: [
        .library(name: "CodeCore", targets: ["CodeCore"])
    ],
    targets: [
        .target(name: "CodeCore", path: "Sources/CodeCore"),
        .testTarget(name: "CodeCoreTests", dependencies: ["CodeCore"], path: "Tests/CodeCoreTests")
    ]
)
