// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitIdentity",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitIdentity", targets: ["SweatKitIdentity"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
    ],
    targets: [
        .target(
            name: "SweatKitIdentity",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
            ]
        ),
        .testTarget(
            name: "SweatKitIdentityTests",
            dependencies: [
                "SweatKitIdentity",
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
            ]
        ),
    ]
)
