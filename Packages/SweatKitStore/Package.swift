// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitStore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitStore", targets: ["SweatKitStore"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitStore",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitStoreTests",
            dependencies: [
                "SweatKitStore",
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
            ]
        ),
    ]
)
