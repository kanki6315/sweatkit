// swift-tools-version: 6.2
import PackageDescription

// Throwaway M0 probe. The client itself is the real package SweatKitGarmin;
// this adds the gate checks, FIT decoding and rate-limit probing around it.
let package = Package(
    name: "GarminPull",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/SweatKitGarmin"),
        .package(url: "https://github.com/garmin/fit-swift-sdk", from: "21.221.0"),
    ],
    targets: [
        .target(
            name: "GarminPullCore",
            dependencies: [
                .product(name: "SweatKitGarmin", package: "SweatKitGarmin"),
                .product(name: "FITSwiftSDK", package: "fit-swift-sdk"),
            ]
        ),
        .executableTarget(name: "GarminPull", dependencies: ["GarminPullCore"]),
        .testTarget(name: "GarminPullCoreTests", dependencies: ["GarminPullCore"]),
    ]
)
