// swift-tools-version: 6.3.2
import PackageDescription

let package = Package(
    name: "bifrost-gage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bifrost-gage", targets: ["BifrostGage"])
    ],
    targets: [
        .executableTarget(
            name: "BifrostGage",
            path: "Sources/BifrostGage"
        )
    ]
)
