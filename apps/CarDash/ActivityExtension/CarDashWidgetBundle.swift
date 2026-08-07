import SwiftUI
import WidgetKit
import CarDashActivity

/// The widget extension's entire contents.
///
/// Everything it draws lives in `CarDashActivity`, which the app links too — that shared link is
/// what makes the `ActivityAttributes` type the same type on both sides of the process boundary.
/// If the app and the extension were to declare their own copies, ActivityKit would match them
/// by name, appear to work, and then fail to route updates in ways that are very hard to see.
///
/// This folder is a buildable folder, so adding a widget here needs no project-file edit.
@main
struct CarDashWidgetBundle: WidgetBundle {
    var body: some Widget {
        NavigationLiveActivity()
    }
}
