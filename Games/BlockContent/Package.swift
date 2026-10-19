// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BlockContent", platforms: [.iOS("18.0")],
    products: [.library(name: "BlockContent", targets: ["BlockContent"]),
               .executable(name: "BlockContentValidator", targets: ["BlockContentValidator"])],
    dependencies: [.package(path: "../../Packages/GameCore")],
    targets: [
        .target(name: "BlockContent", dependencies: [.product(name: "GameCore", package: "GameCore")], resources: [.copy("Resources")]),
        .executableTarget(name: "BlockContentValidator", dependencies: ["BlockContent"]),
        .testTarget(name: "BlockContentTests", dependencies: ["BlockContent"]),
    ], swiftLanguageVersions: [.v5]
)
