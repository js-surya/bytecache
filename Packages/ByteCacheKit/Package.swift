// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ByteCacheKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ByteCacheCore", targets: ["ByteCacheCore"]),
        .library(name: "ByteCacheLanguage", targets: ["ByteCacheLanguage"]),
        .library(name: "ByteCacheFeatures", targets: ["ByteCacheFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/appstefan/HighlightSwift", .upToNextMinor(from: "1.1.0")),
    ],
    targets: [
        // API client, models, auth, offline cache.
        .target(name: "ByteCacheCore"),
        // On-device language detection.
        .target(name: "ByteCacheLanguage", resources: [.process("Resources")]),
        // View models and SwiftUI views shared by the app and share extensions.
        .target(
            name: "ByteCacheFeatures",
            dependencies: ["ByteCacheCore", "ByteCacheLanguage", "HighlightSwift"],
            resources: [.process("Resources")]
        ),
        // Test helpers only; not a product.
        .target(name: "ByteCacheTestSupport", dependencies: ["ByteCacheCore"]),
        .testTarget(
            name: "ByteCacheCoreTests",
            dependencies: ["ByteCacheCore", "ByteCacheTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ByteCacheLanguageTests", dependencies: ["ByteCacheLanguage"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ByteCacheFeaturesTests", dependencies: ["ByteCacheFeatures", "ByteCacheTestSupport"]),
    ]
)
