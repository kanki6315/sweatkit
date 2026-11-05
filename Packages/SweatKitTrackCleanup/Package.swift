// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitTrackCleanup",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitTrackCleanup", targets: ["SweatKitTrackCleanup"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitTrackCleanup",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitTrackCleanupTests",
            dependencies: ["SweatKitTrackCleanup"]
        ),
    ]
)
