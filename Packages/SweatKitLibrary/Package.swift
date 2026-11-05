// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitLibrary",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitLibrary", targets: ["SweatKitLibrary"]),
    ],
    dependencies: [
        .package(path: "../SweatKitModel"),
        .package(path: "../SweatKitCloud"),
        .package(path: "../SweatKitStore"),
        .package(path: "../SweatKitIngest"),
        .package(path: "../SweatKitAnalysis"),
        .package(path: "../SweatKitSync"),
        .package(path: "../SweatKitGarmin"),
        .package(path: "../SweatKitIdentity"),
    ],
    targets: [
        .target(
            name: "SweatKitLibrary",
            dependencies: [
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "SweatKitCloud", package: "SweatKitCloud"),
                .product(name: "SweatKitStore", package: "SweatKitStore"),
                .product(name: "SweatKitIngest", package: "SweatKitIngest"),
                .product(name: "SweatKitAnalysis", package: "SweatKitAnalysis"),
                .product(name: "SweatKitSync", package: "SweatKitSync"),
                .product(name: "SweatKitIdentity", package: "SweatKitIdentity"),
            ]
        ),
        .testTarget(
            name: "SweatKitLibraryTests",
            dependencies: [
                "SweatKitLibrary",
                .product(name: "SweatKitGarmin", package: "SweatKitGarmin"),
                .product(name: "SweatKitModel", package: "SweatKitModel"),
                .product(name: "SweatKitCloud", package: "SweatKitCloud"),
                .product(name: "SweatKitStore", package: "SweatKitStore"),
                .product(name: "SweatKitIngest", package: "SweatKitIngest"),
                .product(name: "SweatKitAnalysis", package: "SweatKitAnalysis"),
                .product(name: "SweatKitSync", package: "SweatKitSync"),
                .product(name: "SweatKitIdentity", package: "SweatKitIdentity"),
                .product(name: "SweatKitTestSupport", package: "SweatKitModel"),
            ]
        ),
    ]
)
