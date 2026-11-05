// swift-tools-version: 6.2
import PackageDescription

// Throwaway M0 spike. Nothing in the app or in Packages/ depends on this.
let package = Package(
    name: "GarminPull",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/garmin/fit-swift-sdk", from: "21.221.0"),
    ],
    targets: [
        .target(
            name: "GarminPullCore",
            dependencies: [.product(name: "FITSwiftSDK", package: "fit-swift-sdk")]
        ),
        .executableTarget(name: "GarminPull", dependencies: ["GarminPullCore"]),
        .testTarget(
            name: "GarminPullCoreTests",
            dependencies: ["GarminPullCore"],
            resources: [.copy("Samples")]
        ),
    ]
)
