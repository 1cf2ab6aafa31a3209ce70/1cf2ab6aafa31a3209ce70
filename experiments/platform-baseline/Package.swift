// swift-tools-version: 5.9
import PackageDescription

// Pure experiment models only; this package is not the production GameCore.
let package = Package(
    name: "PlatformBaselineLogic",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [.library(name: "BaselineLogic", targets: ["BaselineLogic"])],
    targets: [
        .target(name: "BaselineLogic", path: "Sources", exclude: [
            "App", "Board/BoardScene.swift", "Terrain/TerrainProbeView.swift",
            "Diagnostics/ProbeMetrics.swift"
        ], sources: ["Board/BoardGeometry.swift", "Terrain/TerrainHeightfield.swift",
                     "Diagnostics/FrameStatistics.swift"]),
        .testTarget(name: "BaselineLogicTests", dependencies: ["BaselineLogic"], path: "Tests")
    ]
)
