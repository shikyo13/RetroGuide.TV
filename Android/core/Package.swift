// swift-tools-version: 6.0
import PackageDescription

/// The Android app's Swift core: RetroGuideKit plus the coordination the
/// Apple app does in its app layer (servers, lineup, guide, tuning), called
/// from Kotlin through one JSON request function over JNI.
let package = Package(
    name: "RetroGuideCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RetroGuideCore", type: .dynamic, targets: ["RetroGuideCore"]),
    ],
    dependencies: [
        .package(path: "../../Packages/RetroGuideKit"),
    ],
    targets: [
        .target(name: "CJNI"),
        .target(
            name: "RetroGuideCore",
            dependencies: ["CJNI", .product(name: "RetroGuideKit", package: "RetroGuideKit")]
        ),
        .testTarget(name: "RetroGuideCoreTests", dependencies: ["RetroGuideCore"]),
    ]
)
