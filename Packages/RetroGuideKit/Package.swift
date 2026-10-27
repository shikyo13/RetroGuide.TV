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
            resources: [.process("Resources")],
            // Scheduling simulates every channel from the schedule epoch at
            // launch; unoptimized, that's ~25x slower. Optimizing Debug builds
            // too keeps development and test builds representative.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(
            name: "RetroGuideKitTests",
            dependencies: ["RetroGuideKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
