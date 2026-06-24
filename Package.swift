// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stowly",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Stowly",
            dependencies: [
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
            ],
            path: "Sources/Stowly",
            resources: [
                .copy("Resources/extract_reel.py")
            ]
        ),
        .testTarget(
            name: "StowlyTests",
            dependencies: ["Stowly"],
            path: "Tests/StowlyTests"
        )
    ]
)
