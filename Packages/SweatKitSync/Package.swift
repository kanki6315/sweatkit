// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitSync",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitSync", targets: ["SweatKitSync"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
        .package(path: "../SweatKitGarmin"),
    ],
    targets: [
        .target(
            name: "SweatKitSync",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "SweatKitGarmin", package: "SweatKitGarmin"),
            ]
        ),
        .testTarget(
            name: "SweatKitSyncTests",
            dependencies: ["SweatKitSync"]
        ),
    ]
)
