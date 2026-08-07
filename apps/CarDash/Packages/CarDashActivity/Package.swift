// swift-tools-version: 6.0
import PackageDescription

// The Live Activity's shared vocabulary and its widget views.
//
// A third package rather than putting this in CarDashKit, for one concrete reason: both the app
// and the widget extension must link whatever declares the `ActivityAttributes` type, and
// CarDashKit pulls in MapKit, AVFoundation, MediaPlayer, ContactsUI and MessageUI. A widget
// extension runs under a memory limit measured in tens of megabytes; handing it the entire
// dashboard to link so it can read one struct would be a poor trade.
//
// It depends on CarDashCore, where the state and every presentation decision live, so the only
// thing here that cannot be tested on Linux is the drawing.
let package = Package(
    name: "CarDashActivity",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "CarDashActivity", targets: ["CarDashActivity"])
    ],
    dependencies: [
        .package(name: "CarDashCore", path: "../CarDashCore")
    ],
    targets: [
        .target(
            name: "CarDashActivity",
            dependencies: [
                .product(name: "CarDashCore", package: "CarDashCore")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
