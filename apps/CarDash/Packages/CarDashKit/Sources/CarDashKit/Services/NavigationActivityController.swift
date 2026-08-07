import ActivityKit
import Foundation
import Observation
import CarDashCore
import CarDashActivity
import os

/// Owns the turn-by-turn Live Activity.
///
/// The reason it exists: when the phone locks, the dashboard is gone. Navigation keeps running —
/// the location background mode sees to that — but the screen the driver was reading does not,
/// and a phone in a mount locks constantly. This puts the next manoeuvre back on the lock screen
/// and in the Dynamic Island.
///
/// Two things govern the design, and both are budgets rather than preferences:
///
/// **Update rate.** ActivityKit throttles updates and each one costs power. Pushing a new state
/// on every location fix — roughly one a second while moving — would be throttled anyway and
/// would drain the battery of a phone that is usually charging but not always. So updates are
/// sent when the *displayed* content would actually change, which on a long motorway stretch can
/// be minutes apart. The countdown keeps running in between because the widget renders the
/// arrival date rather than a frozen string.
///
/// **Failure is silent and fine.** Live Activities can be disabled system-wide, per app, or
/// refused when too many are already running. Every call here therefore does nothing rather than
/// throwing, and navigation is unaffected — the Live Activity is an enhancement to a feature that
/// works without it.
@MainActor
@Observable
public final class NavigationActivityController {
    /// False when the user has switched Live Activities off for this app, which is worth being
    /// able to surface rather than leaving them wondering why the lock screen is empty.
    public var isEnabledBySystem: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public private(set) var isRunning = false

    @ObservationIgnored private var activity: Activity<NavigationAttributes>?
    @ObservationIgnored private var lastPublished: NavigationActivityState?
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "live-activity")

    public init() {}

    // MARK: - Lifecycle

    /// Starts an activity for a route, replacing any that was already running.
    public func start(destination: String, state: NavigationActivityState) {
        guard isEnabledBySystem else {
            Self.log.info("live activities are switched off for this app")
            return
        }
        // Starting a second activity for a new route while the old one is still up would leave
        // two navigation banners on the lock screen, one of them permanently stale.
        if activity != nil { end() }

        do {
            activity = try Activity.request(
                attributes: NavigationAttributes(destinationName: destination),
                content: ActivityContent(state: state, staleDate: staleDate(for: state)),
                pushType: nil
            )
            lastPublished = state
            isRunning = true
        } catch {
            // Refused for a reason the app cannot fix — too many activities, or the setting
            // changed between the check and the request. Navigation carries on regardless.
            Self.log.error("could not start the live activity: \(error)")
            isRunning = false
        }
    }

    /// Pushes a new state, if it would actually look different.
    public func update(_ state: NavigationActivityState) {
        guard let activity else { return }
        guard shouldPublish(state) else { return }

        lastPublished = state
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: staleDate(for: state))
            )
        }
    }

    /// Ends the activity showing a final state, and leaves it up for a minute.
    ///
    /// Separate from `end()` because arriving is the one case where the last thing pushed
    /// matters. Calling `update` and then `end` would race — they are two independent tasks —
    /// and the banner could vanish still showing the last turn instead of the arrival.
    public func finish(with state: NavigationActivityState) {
        guard let activity else { return }
        self.activity = nil
        lastPublished = nil
        isRunning = false

        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + 60)
            )
        }
    }

    /// Ends the activity, leaving the arrival banner up briefly when the route completed.
    public func end(arrived: Bool = false) {
        guard let activity else { return }
        self.activity = nil
        lastPublished = nil
        isRunning = false

        let policy: ActivityUIDismissalPolicy = arrived ? .after(.now + 60) : .immediate
        Task {
            await activity.end(nil, dismissalPolicy: policy)
        }
    }

    /// Ends anything left over from a previous launch.
    ///
    /// A Live Activity outlives the process that started it. If the app was killed mid-route —
    /// or crashed — the banner stays on the lock screen showing a manoeuvre from a drive that
    /// finished hours ago, and nothing else will ever clear it.
    public func endOrphanedActivities() {
        for stale in Activity<NavigationAttributes>.activities where stale.id != activity?.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Rate limiting

    /// Whether the new state would change what the driver sees.
    ///
    /// The comparison is on the rendered strings rather than the raw metres, which is the point:
    /// moving 12 metres changes `distanceRemaining` as a number and changes nothing as text, and
    /// there is no reason to spend an update on it.
    private func shouldPublish(_ state: NavigationActivityState) -> Bool {
        guard let last = lastPublished else { return true }

        if state.hasArrived != last.hasArrived { return true }
        if state.instruction != last.instruction { return true }
        if state.maneuverSymbol != last.maneuverSymbol { return true }
        if state.distanceToManeuver != last.distanceToManeuver { return true }
        if state.distanceRemaining != last.distanceRemaining { return true }

        // The arrival time is rendered as a clock, so only a change of a minute or more shows.
        // Without this an ETA drifting by seconds would push an update on every single fix.
        return abs(state.arrivalDate.timeIntervalSince(last.arrivalDate)) >= 60
    }

    /// When the system should start showing this content as out of date.
    ///
    /// Set generously: going through a tunnel stops the fixes, and a lock screen that greys
    /// itself out after thirty seconds of no signal is worse than one showing a slightly old
    /// distance.
    private func staleDate(for state: NavigationActivityState) -> Date {
        Date().addingTimeInterval(state.hasArrived ? 300 : 180)
    }
}
