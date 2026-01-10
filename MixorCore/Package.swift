// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MixorCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MixorCore",
            targets: ["MixorCore"]
        ),
    ],
    targets: [
        .target(
            name: "MixorCore",
            dependencies: []
        ),
    ]
)
