// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ByteCatchKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ByteCatchCore", targets: ["ByteCatchCore"]),
        .library(name: "ByteCatchLanguage", targets: ["ByteCatchLanguage"]),
        .library(name: "ByteCatchFeatures", targets: ["ByteCatchFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/appstefan/HighlightSwift", .upToNextMinor(from: "1.1.0")),
    ],
    targets: [
        // API client, models, auth, offline cache.
        .target(name: "ByteCatchCore"),
        // On-device language detection.
        .target(name: "ByteCatchLanguage", resources: [.process("Resources")]),
        // View models and SwiftUI views shared by the app and share extensions.
        .target(
            name: "ByteCatchFeatures",
            dependencies: ["ByteCatchCore", "ByteCatchLanguage", "HighlightSwift"],
            resources: [.process("Resources")]
        ),
        // Test helpers only; not a product.
        .target(name: "ByteCatchTestSupport", dependencies: ["ByteCatchCore"]),
        .testTarget(
            name: "ByteCatchCoreTests",
            dependencies: ["ByteCatchCore", "ByteCatchTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ByteCatchLanguageTests", dependencies: ["ByteCatchLanguage"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ByteCatchFeaturesTests", dependencies: ["ByteCatchFeatures", "ByteCatchTestSupport"]),
    ]
)
