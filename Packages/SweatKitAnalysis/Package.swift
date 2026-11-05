// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitAnalysis",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitAnalysis", targets: ["SweatKitAnalysis"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitAnalysis",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitAnalysisTests",
            dependencies: [
                "SweatKitAnalysis",
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
            ]
        ),
    ]
)
