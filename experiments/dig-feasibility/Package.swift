// swift-tools-version: 5.9
import PackageDescription

// Disposable Spike 11 experiment. Renderer-free rules, fields and CPU geometry;
// not a production package. macOS is only the command-line test/benchmark host.
let package = Package(
    name: "DigFeasibility",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [.library(name: "DigCore", targets: ["DigCore"])],
    dependencies: [.package(path: "../../Packages/GameCore")],
    targets: [
        .target(name: "DigCore", dependencies: [.product(name: "GameCore", package: "GameCore")]),
        .executableTarget(name: "DigBench", dependencies: ["DigCore"]),
        .testTarget(
            name: "DigCoreTests",
            dependencies: ["DigCore", .product(name: "GameCore", package: "GameCore")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
