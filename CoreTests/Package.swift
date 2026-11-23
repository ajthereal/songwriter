// swift-tools-version: 5.9
import PackageDescription

// Sources/Core is populated by ci/run.sh (copies the pure Swift files from Songwriter.swiftpm).
let package = Package(
    name: "CoreTests",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Core", targets: ["Core"])],
    targets: [
        .target(name: "Core", path: "Sources/Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
    ]
)
