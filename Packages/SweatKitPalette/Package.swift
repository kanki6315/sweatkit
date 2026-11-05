// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweatKitPalette",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SweatKitPalette", targets: ["SweatKitPalette"]),
    ],
    targets: [
        .target(name: "SweatKitPalette"),
        .testTarget(name: "SweatKitPaletteTests", dependencies: ["SweatKitPalette"]),
    ]
)
