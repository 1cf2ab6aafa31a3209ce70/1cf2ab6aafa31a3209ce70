// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TileContent", platforms: [.iOS("18.0")],
    products: [.library(name: "TileContent", targets: ["TileContent"]),
               .executable(name: "TileContentValidator", targets: ["TileContentValidator"])],
    dependencies: [.package(path: "../../Packages/GameCore")],
    targets: [
        .target(name: "TileContent", dependencies: [.product(name: "GameCore", package: "GameCore")], resources: [.copy("Resources")]),
        .executableTarget(name: "TileContentValidator", dependencies: ["TileContent"]),
        .testTarget(name: "TileContentTests", dependencies: ["TileContent"]),
    ], swiftLanguageVersions: [.v5]
)
