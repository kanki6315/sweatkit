// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitModel",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitModel", targets: ["SweatKitModel"]),
        .library(name: "SweatKitTestSupport", targets: ["SweatKitTestSupport"]),
    ],
    targets: [
        .target(name: "SweatKitModel"),
        .target(name: "SweatKitTestSupport", dependencies: ["SweatKitModel"]),
        .testTarget(
            name: "SweatKitModelTests",
            dependencies: ["SweatKitModel", "SweatKitTestSupport"]
        ),
    ]
)
