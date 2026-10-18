// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlexaKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AlexaKit", targets: ["AlexaKit"])],
    targets: [
        .target(name: "AlexaKit"),
        .testTarget(name: "AlexaKitTests", dependencies: ["AlexaKit"]),
    ]
)
