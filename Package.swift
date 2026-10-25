// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sonorist",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Sonorist",
            targets: ["Sonorist"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Sonorist",
            dependencies: [],
            path: "Sources/Sonorist"
        ),
        .testTarget(
            name: "SonoristTests",
            dependencies: ["Sonorist"],
            path: "Tests/SonoristTests"
        ),
    ]
)
