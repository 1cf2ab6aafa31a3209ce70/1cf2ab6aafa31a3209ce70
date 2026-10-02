// swift-tools-version: 5.9
import PackageDescription

// Investigation only: no production package depends on this executable.
let package = Package(
    name: "SaveDurabilityFixture",
    products: [.executable(name: "save-durability-fixture", targets: ["SaveDurabilityFixture"])],
    targets: [.executableTarget(name: "SaveDurabilityFixture")]
)
