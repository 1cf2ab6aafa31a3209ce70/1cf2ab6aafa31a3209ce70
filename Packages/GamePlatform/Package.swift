// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GamePlatform",
    // macOS is the command-line test host; the application remains mobile-only.
    platforms: [.iOS("18.0"), .macOS(.v10_15)],
    products: [.library(name: "GamePlatform", targets: ["GamePlatform"])],
    dependencies: [.package(path: "../GameCore")],
    targets: [
        .target(
            name: "GamePlatform",
            dependencies: [.product(name: "GameCore", package: "GameCore")]
        ),
        .testTarget(name: "GamePlatformTests", dependencies: ["GamePlatform"]),
    ],
    swiftLanguageVersions: [.v5]
)
