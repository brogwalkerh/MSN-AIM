import SwiftUI
import CarDashCore

enum ClockSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .clock,
            title: "Clock",
            systemImage: "clock.fill",
            blurb: "The time, large enough to read at a glance."
        ) { context in
            AnyView(ClockPaneView(context: context))
        }
    }
}

struct ClockPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme

    var body: some View {
        // Ticks once a minute rather than once a second. Seconds are of no use to a
        // driver and would wake the view sixty times more often, which on a screen kept
        // permanently awake is a real battery and thermal cost.
        TimelineView(.everyMinute) { timeline in
            VStack(spacing: context.environment.isCompact ? 0 : 4) {
                Text(timeline.date, format: .dateTime.hour().minute())
                    .font(.system(
                        size: context.environment.isCompact ? 44 : 64,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(theme.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if !context.environment.isCompact {
                    Text(timeline.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(DashFont.label(14))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .panePadding()
        }
        .accessibilityElement()
        .accessibilityLabel("Clock")
    }
}
