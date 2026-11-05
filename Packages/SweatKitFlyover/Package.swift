// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitFlyover",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitFlyover", targets: ["SweatKitFlyover"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitFlyover",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitFlyoverTests",
            dependencies: ["SweatKitFlyover"]
        ),
    ]
)
