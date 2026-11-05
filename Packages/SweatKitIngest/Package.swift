// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitIngest",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitIngest", targets: ["SweatKitIngest"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
        .package(url: "https://github.com/garmin/fit-swift-sdk", from: "21.221.0"),
    ],
    targets: [
        .target(
            name: "SweatKitIngest",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "FITSwiftSDK", package: "fit-swift-sdk"),
            ]
        ),
        .testTarget(
            name: "SweatKitIngestTests",
            dependencies: [
                "SweatKitIngest",
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
                .product(name: "FITSwiftSDK", package: "fit-swift-sdk"),
            ]
        ),
    ]
)
