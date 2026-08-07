import ActivityKit
import Foundation
import CarDashCore

/// The Live Activity's identity.
///
/// Deliberately almost empty. ActivityKit splits an activity into fixed *attributes*, set once
/// when it starts, and a *content state* that is replaced on every update. Anything that changes
/// while driving belongs in the state, and on a route that is nearly everything — so the
/// attributes hold only the destination, which does not change until the route does.
///
/// The content state is `NavigationActivityState` from CarDashCore, which is where all the
/// presentation decisions are made and tested. Nothing is computed on this side of the process
/// boundary.
public struct NavigationAttributes: ActivityAttributes {
    public typealias ContentState = NavigationActivityState

    /// "Home", "Gatwick Airport" — whatever the user searched for.
    public var destinationName: String

    public init(destinationName: String) {
        self.destinationName = destinationName
    }
}
