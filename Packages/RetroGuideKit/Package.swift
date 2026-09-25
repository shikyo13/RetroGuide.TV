// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetroGuideKit",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "RetroGuideKit", targets: ["RetroGuideKit"]),
    ],
    targets: [
        .target(
            name: "RetroGuideKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RetroGuideKitTests",
            dependencies: ["RetroGuideKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
