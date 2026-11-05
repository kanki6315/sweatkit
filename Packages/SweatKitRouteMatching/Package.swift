// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitRouteMatching",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitRouteMatching", targets: ["SweatKitRouteMatching"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitRouteMatching",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitRouteMatchingTests",
            dependencies: [
                "SweatKitRouteMatching",
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
            ]
        ),
    ]
)
