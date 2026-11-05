// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitTimeline",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitTimeline", targets: ["SweatKitTimeline"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitTimeline",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitTimelineTests",
            dependencies: [
                "SweatKitTimeline",
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
    ]
)
