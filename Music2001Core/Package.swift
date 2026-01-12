// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Music2001Core",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Music2001Core",
            targets: ["Music2001Core"]
        ),
    ],
    targets: [
        .target(
            name: "Music2001Core",
            dependencies: []
        ),
    ]
)
