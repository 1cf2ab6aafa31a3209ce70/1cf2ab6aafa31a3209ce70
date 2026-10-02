// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "DevelopmentContent", platforms: [.iOS("18.0")],
    products: [.library(name: "DevelopmentContent", targets: ["DevelopmentContent"]),
               .executable(name: "content-validator", targets: ["ContentValidatorCLI"])],
    dependencies: [.package(path: "../../Packages/GameCore")],
    targets: [
        .target(name: "DevelopmentContent", dependencies: [.product(name: "GameCore", package: "GameCore")], resources: [.copy("Resources")]),
        .executableTarget(name: "ContentValidatorCLI", dependencies: ["DevelopmentContent"]),
        .testTarget(name: "DevelopmentContentTests", dependencies: ["DevelopmentContent"]),
    ], swiftLanguageVersions: [.v5]
)
