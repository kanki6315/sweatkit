// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitGarmin",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitGarmin", targets: ["SweatKitGarmin"]),
    ],
    targets: [
        .target(name: "SweatKitGarmin"),
        .testTarget(
            name: "SweatKitGarminTests",
            dependencies: ["SweatKitGarmin"],
            resources: [.copy("Samples")]
        ),
    ]
)
