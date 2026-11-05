// swift-tools-version: 6.2
import PackageDescription

// The layer above the detail screen's leaf packages: it turns one activity's
// analysis stream into what the flyover and the timeline take. Unlike the
// leaf packages it depends on several of them, by design.
let package = Package(
    name: "SweatKitDetail",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitDetail", targets: ["SweatKitDetail"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
        .package(path: "../SweatKitAnalysis"),
        .package(path: "../SweatKitTrackCleanup"),
        .package(path: "../SweatKitFlyover"),
        .package(path: "../SweatKitTimeline"),
        .package(path: "../SweatKitIngest"),
    ],
    targets: [
        .target(
            name: "SweatKitDetail",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "SweatKitAnalysis", package: "SweatKitAnalysis"),
                .product(name: "SweatKitTrackCleanup", package: "SweatKitTrackCleanup"),
                .product(name: "SweatKitFlyover", package: "SweatKitFlyover"),
                .product(name: "SweatKitTimeline", package: "SweatKitTimeline"),
            ]
        ),
        .testTarget(
            name: "SweatKitDetailTests",
            dependencies: [
                "SweatKitDetail",
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
                .product(name: "SweatKitAnalysis", package: "SweatKitAnalysis"),
                .product(name: "SweatKitTrackCleanup", package: "SweatKitTrackCleanup"),
                .product(name: "SweatKitFlyover", package: "SweatKitFlyover"),
                .product(name: "SweatKitTimeline", package: "SweatKitTimeline"),
                .product(name: "SweatKitIngest", package: "SweatKitIngest"),
            ]
        ),
    ]
)
