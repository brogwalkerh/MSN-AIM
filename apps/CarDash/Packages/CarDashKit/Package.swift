// swift-tools-version: 6.0
import PackageDescription

// Everything that needs Apple frameworks lives here. This target cannot be compiled on
// Linux, so it is verified only by the `xcodebuild` job on a macOS runner — keep logic
// that can live in CarDashCore in CarDashCore.
//
// Swift language mode is v5 here on purpose. CarDashCore is pure value types and runs
// in v6 strict-concurrency mode happily; this target is SwiftUI + AVFoundation +
// CoreLocation delegates, where v6 isolation checking produces a large amount of churn
// that cannot be iterated on locally (every round trip is a CI run). Tightened to v6
// once the surface stops moving.
let package = Package(
    name: "CarDashKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "CarDashKit", targets: ["CarDashKit"])
    ],
    dependencies: [
        .package(name: "CarDashCore", path: "../CarDashCore")
    ],
    targets: [
        .target(
            name: "CarDashKit",
            dependencies: [
                .product(name: "CarDashCore", package: "CarDashCore")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
