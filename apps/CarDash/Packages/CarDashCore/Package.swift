// swift-tools-version: 6.0
import PackageDescription

// CarDashCore imports NOTHING but Foundation.
//
// That is not incidental tidiness — it is the testing strategy. The machine that
// develops this app has no macOS and no Xcode, so the only way to *prove* the layout
// algebra, persistence, playback state machine and guidance engine are correct is to
// run them under `swift test` on Linux in CI. The moment this target imports SwiftUI,
// CoreGraphics or MapKit, that proof disappears.
//
// This is why the package defines its own LayoutRect/LayoutSize/LayoutPoint instead of
// using CGRect and friends: CoreGraphics does not exist on Linux.
//
// `platforms` only constrains Apple platforms — it has no bearing on the Linux build,
// which is why declaring it costs nothing here. It has to be declared: without it,
// Xcode builds this package against SwiftPM's ancient default iOS deployment target and
// rejects any API newer than iOS 12, even though the app itself requires iOS 26.
let package = Package(
    name: "CarDashCore",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "CarDashCore", targets: ["CarDashCore"])
    ],
    targets: [
        .target(
            name: "CarDashCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CarDashCoreTests",
            dependencies: ["CarDashCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
