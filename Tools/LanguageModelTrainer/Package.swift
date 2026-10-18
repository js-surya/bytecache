// swift-tools-version: 6.0
import PackageDescription

// Trains ByteCatch's language model. macOS only (Create ML). Not part of the app.
let package = Package(
    name: "LanguageModelTrainer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/ByteCatchKit")],
    targets: [
        .executableTarget(
            name: "train",
            dependencies: [.product(name: "ByteCatchLanguage", package: "ByteCatchKit")]
        ),
    ]
)
