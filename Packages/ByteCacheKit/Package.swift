// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ByteCacheKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
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
            resources: [.process("Resources")],
            // The Ko-fi link exists only in Debug and GitHub builds (scripts/package-release.sh adds
            // TIP_LINKS): App Store and TestFlight apps may not link to outside tip pages (3.1.1).
            swiftSettings: [.define("TIP_LINKS", .when(configuration: .debug))]
        ),
        // Test helpers only; not a product.
        .target(name: "ByteCacheTestSupport", dependencies: ["ByteCacheCore"]),
        .testTarget(
            name: "ByteCacheCoreTests",
            dependencies: ["ByteCacheCore", "ByteCacheTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ByteCacheLanguageTests", dependencies: ["ByteCacheLanguage"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ByteCacheFeaturesTests", dependencies: ["ByteCacheFeatures", "ByteCacheTestSupport"],
                    swiftSettings: [.define("TIP_LINKS", .when(configuration: .debug))]),
    ]
)
