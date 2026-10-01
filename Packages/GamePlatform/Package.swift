// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GamePlatform",
    platforms: [.iOS("18.0")],
    products: [.library(name: "GamePlatform", targets: ["GamePlatform"])],
    dependencies: [.package(path: "../GameCore")],
    targets: [
        .target(
            name: "GamePlatform",
            dependencies: [.product(name: "GameCore", package: "GameCore")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
