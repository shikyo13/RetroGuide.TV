// swift-tools-version: 6.0
import PackageDescription

/// Builds `title-classification.bin`, RetroGuideKit's table of what well-known
/// titles are, from Wikidata (CC0). Run from this folder:
///
///     swift run -c release title-classifier fetch
///     swift run -c release title-classifier build
let package = Package(
    name: "TitleClassifier",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/RetroGuideKit")],
    targets: [
        .executableTarget(
            name: "title-classifier",
            dependencies: [.product(name: "RetroGuideKit", package: "RetroGuideKit")],
            path: "Sources/TitleClassifier"
        ),
    ]
)
