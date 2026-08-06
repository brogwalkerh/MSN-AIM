import SwiftUI
import CarDashKit

/// The app target is intentionally a thin shell — a handful of lines that hand off to
/// `CarDashKit`. Everything testable lives in the packages, because the packages are
/// what CI can reach.
@main
struct CarDashApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // The home indicator is a distraction on a mounted phone, and an
                // accidental edge swipe while driving should not dump the driver out
                // to the home screen mid-route.
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
        }
    }
}
