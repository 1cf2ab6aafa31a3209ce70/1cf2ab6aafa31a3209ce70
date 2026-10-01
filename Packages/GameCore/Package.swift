// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [.iOS("18.0")],
    products: [.library(name: "GameCore", targets: ["GameCore"])],
    targets: [
        .target(name: "GameCore"),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
