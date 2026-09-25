// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetroTVKit",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "RetroTVKit", targets: ["RetroTVKit"]),
    ],
    targets: [
        .target(
            name: "RetroTVKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RetroTVKitTests",
            dependencies: ["RetroTVKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
