// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SweatKitCloud", platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "SweatKitCloud", targets: ["SweatKitCloud"])],
    dependencies: [.package(path: "../SweatKitModel")],
    targets: [.target(name: "SweatKitCloud", dependencies: [.product(name: "SweatKitModel", package: "SweatKitModel")]),
              .testTarget(name: "SweatKitCloudTests", dependencies: ["SweatKitCloud"])])
