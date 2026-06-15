// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BifrostBudgetBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BifrostBudgetBar", targets: ["BifrostBudgetBar"])
    ],
    targets: [
        .executableTarget(
            name: "BifrostBudgetBar",
            path: "Sources/BifrostBudgetBar"
        )
    ]
)
