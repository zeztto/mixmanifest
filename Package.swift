// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MixManifest",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MixManifestCore", targets: ["MixManifestCore"]), .executable(name: "MixManifest", targets: ["MixManifestApp"])],
    targets: [
        .target(name: "MixManifestCore"),
        .executableTarget(name: "MixManifestApp", dependencies: ["MixManifestCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["MixManifestCore"], path: "Tests/MixManifestCoreTests")
    ]
)
