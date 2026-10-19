// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "__CONTENT__", platforms: [.iOS("18.0")],
    products: [.library(name: "__CONTENT__", targets: ["__CONTENT__"]),
               .executable(name: "__CONTENT__Validator", targets: ["__CONTENT__Validator"])],
    dependencies: [.package(path: "../../Packages/GameCore")],
    targets: [
        .target(name: "__CONTENT__", dependencies: [.product(name: "GameCore", package: "GameCore")], resources: [.copy("Resources")]),
        .executableTarget(name: "__CONTENT__Validator", dependencies: ["__CONTENT__"]),
        .testTarget(name: "__CONTENT__Tests", dependencies: ["__CONTENT__"]),
    ], swiftLanguageVersions: [.v5]
)
