// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SportsKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SportsKit", targets: ["SportsKit"]),
    ],
    targets: [
        .target(name: "SportsKit"),
        .testTarget(
            name: "SportsKitTests",
            dependencies: ["SportsKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
