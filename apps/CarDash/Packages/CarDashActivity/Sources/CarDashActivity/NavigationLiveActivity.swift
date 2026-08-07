import ActivityKit
import SwiftUI
import WidgetKit
import CarDashCore

/// The turn-by-turn Live Activity: lock screen, Dynamic Island, and the minimal pill.
///
/// The one thing worth understanding about this file is that it draws and nothing else. Every
/// string it shows was decided in `NavigationActivityState.from(_:units:now:)` back in the app's
/// process, because this code runs in a widget extension where none of it can be tested. If a
/// distance is in the wrong units or a manoeuvre arrow is wrong, the bug is in CarDashCore and
/// there is a test to add for it there.
///
/// The exception, and it is deliberate: the two countdowns use SwiftUI's own date rendering
/// rather than a formatted string. A Live Activity is only updated when the app has something
/// new to say, which on a motorway can be minutes apart, and a frozen "14 min" on a lock screen
/// is worse than no estimate at all. `Text(_:style:)` keeps counting between updates.
public struct NavigationLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationAttributes.self) { context in
            LockScreenView(destination: context.attributes.destinationName, state: context.state)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.maneuverSymbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.state.distanceToManeuver)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(context.state.arrivalDate, style: .time)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.instruction)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.maneuverSymbol)
                    .foregroundStyle(.orange)
            } compactTrailing: {
                // The compact trailing slot is a few characters wide, so it gets the one
                // number that matters at a glance: how far to the next turn.
                Text(context.state.distanceToManeuver)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } minimal: {
                Image(systemName: context.state.maneuverSymbol)
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}

/// The lock-screen banner.
///
/// Sized for a glance from a windscreen mount rather than from the hand, which is why the
/// manoeuvre arrow and the distance are the two largest things on it and the street name is not.
struct LockScreenView: View {
    let destination: String
    let state: NavigationActivityState

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Image(systemName: state.maneuverSymbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.orange)
                if !state.hasArrived {
                    Text(state.distanceToManeuver)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 74)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.instruction)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if state.hasArrived {
                    Text(destination)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                } else {
                    HStack(spacing: 6) {
                        // Counts down on its own between updates, which on a long motorway
                        // stretch may be several minutes apart.
                        Text(state.arrivalDate, style: .timer)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .monospacedDigit()

                        Text("·")
                            .foregroundStyle(.white.opacity(0.4))

                        Text(state.distanceRemaining)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))

                        Text("·")
                            .foregroundStyle(.white.opacity(0.4))

                        Text(state.arrivalDate, style: .time)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
