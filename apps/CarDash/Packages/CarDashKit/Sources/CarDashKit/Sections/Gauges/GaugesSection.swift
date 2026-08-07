import SwiftUI
import CarDashCore

enum GaugesSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .gauges,
            title: "Gauges",
            systemImage: "gauge.with.dots.needle.50percent",
            blurb: "Speed, heading, altitude and trip meter, from GPS. No account needed.",
            capabilities: [.needsLocation]
        ) { context in
            AnyView(GaugesPaneView(context: context))
        }
    }
}

struct GaugesPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme

    private var location: LocationService { context.services.location }
    private var units: UnitSystem { context.services.unitSystem }

    var body: some View {
        VStack(spacing: 4) {
            speedReadout

            if !context.environment.isCompact {
                secondaryReadouts
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panePadding()
        .contentShape(Rectangle())
        // Resetting the trip is destructive and easy to hit by accident on a bumpy road,
        // so it is behind a long press rather than a tap.
        .onLongPressGesture(minimumDuration: 0.6) {
            location.resetTrip()
            Haptics.success()
        }
        .accessibilityElement(children: .combine)
    }

    private var speedReadout: some View {
        VStack(spacing: -4) {
            // Nil, not zero, when there is no fix. A speedometer confidently reading 0
            // while moving is worse than one admitting it does not know.
            if let speed = UnitFormatting.speedValue(metersPerSecond: location.speed, system: units) {
                Text("\(speed)")
                    .font(.system(
                        size: context.environment.isCompact ? 44 : 76,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(theme.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: speed)
            } else {
                Text("––")
                    .font(.system(
                        size: context.environment.isCompact ? 44 : 76,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(theme.secondaryText)
            }

            Text(units.speedLabel)
                .font(DashFont.label(context.environment.isCompact ? 11 : 14))
                .foregroundStyle(theme.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private var secondaryReadouts: some View {
        HStack(spacing: 0) {
            readout(
                title: "Heading",
                value: location.course.map { UnitFormatting.compassPoint(degrees: $0) } ?? "––"
            )
            readout(
                title: "Trip",
                value: UnitFormatting.distance(meters: location.trip.distance, system: units)
            )
            if !context.environment.isNarrow {
                readout(
                    title: "Altitude",
                    value: location.altitude.map {
                        UnitFormatting.distance(meters: $0, system: units)
                    } ?? "––"
                )
            }
        }
    }

    private func readout(title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(DashFont.value(17))
                .foregroundStyle(theme.primaryText)
                .monospacedDigit()
            Text(title)
                .font(DashFont.label(10))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
