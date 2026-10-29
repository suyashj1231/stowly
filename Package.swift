// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stowly",
    platforms: [
        .macOS("27.0"),  // Apple on-device model (Foundation Models + image attachments)
        .iOS(.v17)       // StowlyShared only, for the iPhone app
    ],
    products: [
        .executable(name: "Stowly", targets: ["Stowly"]),
        .library(name: "StowlyShared", targets: ["StowlyShared"])   // used by StowlyiOS
    ],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", from: "1.1.0")
    ],
    targets: [
        // Platform detection, link extraction and pairing parsing, shared with the iPhone app.
        .target(
            name: "StowlyShared",
            path: "Sources/StowlyShared"
        ),
        .executableTarget(
            name: "Stowly",
            dependencies: [
                "StowlyShared",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
            ],
            path: "Sources/Stowly",
            resources: [
                .copy("Resources/extract_reel.py")
            ]
        ),
        .testTarget(
            name: "StowlyTests",
            dependencies: ["Stowly", "StowlyShared"],
            path: "Tests/StowlyTests"
        )
    ]
)
