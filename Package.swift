// swift-tools-version: 6.3.2
import PackageDescription

let package = Package(
    name: "bifrost-gauge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bifrost-gauge", targets: ["BifrostGauge"])
    ],
    targets: [
        .executableTarget(
            name: "BifrostGauge",
            path: "Sources/BifrostGauge"
        ),
        .testTarget(
            name: "BifrostGaugeTests",
            dependencies: ["BifrostGauge"],
            path: "Tests/BifrostGaugeTests"
        )
    ]
)
