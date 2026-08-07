import SwiftUI
import CarDashCore

extension WeatherCondition {
    /// SF Symbol for a condition. Lives here rather than in Core because symbol names
    /// are a rendering concern, and Core must stay free of anything Apple-specific.
    func symbolName(isDaylight: Bool) -> String {
        switch self {
        case .clear: return isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear: return isDaylight ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: return isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .freezingDrizzle, .freezingRain: return "cloud.sleet.fill"
        case .rain: return "cloud.rain.fill"
        case .showers: return isDaylight ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .snow, .snowGrains, .snowShowers: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .thunderstormWithHail: return "cloud.bolt.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum WeatherSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .weather,
            title: "Weather",
            systemImage: "cloud.sun.fill",
            blurb: "Current conditions and the next few hours.",
            capabilities: [.needsLocation, .needsNetwork]
        ) { context in
            AnyView(WeatherPaneView(context: context))
        }
    }
}

struct WeatherPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme
    @Environment(\.openURL) private var openURL

    private var store: WeatherStore { context.services.weather }
    private var units: UnitSystem { context.services.unitSystem }

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                content(snapshot)
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panePadding()
        .task(id: context.services.location.coordinate) {
            store.refresh(for: context.services.location.coordinate)
        }
    }

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: snapshot.current.condition.symbolName(
                    isDaylight: snapshot.current.isDaylight
                ))
                .font(.system(size: context.environment.isCompact ? 24 : 34))
                .foregroundStyle(theme.accent)
                .symbolRenderingMode(.hierarchical)

                Text(UnitFormatting.temperature(celsius: snapshot.current.temperature, system: units))
                    .font(DashFont.value(context.environment.isCompact ? 32 : 44))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 0)
            }

            Text(snapshot.current.condition.describedBriefly)
                .font(DashFont.label(context.environment.isCompact ? 12 : 14))
                .foregroundStyle(
                    snapshot.current.condition.isHazardous ? theme.accent : theme.secondaryText
                )
                .lineLimit(1)

            if !context.environment.isCompact {
                Spacer(minLength: 0)
                hourlyStrip(snapshot)
            }

            Spacer(minLength: 0)
            attribution(snapshot.attribution)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hourlyStrip(_ snapshot: WeatherSnapshot) -> some View {
        let hours = snapshot.upcoming(from: Date(), count: context.environment.isNarrow ? 3 : 5)
        return HStack(spacing: 0) {
            ForEach(hours) { hour in
                VStack(spacing: 3) {
                    Text(hour.time, format: .dateTime.hour())
                        .font(DashFont.label(10))
                        .foregroundStyle(theme.secondaryText)
                    Image(systemName: hour.condition.symbolName(isDaylight: true))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                    Text(UnitFormatting.temperature(celsius: hour.temperature, system: units))
                        .font(DashFont.label(12))
                        .foregroundStyle(theme.primaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Required by the data licence, not decorative.
    ///
    /// `SectionMetrics` gives this tile a minimum height that guarantees room for this
    /// line — Open-Meteo is CC BY, and WeatherKit's terms are stricter still. If a
    /// layout change ever seems to call for shrinking the weather tile, this is why it
    /// cannot be shrunk past that floor.
    private func attribution(_ attribution: WeatherAttribution) -> some View {
        Button {
            if let url = attribution.legalURL { openURL(url) }
        } label: {
            Text(attribution.name)
                .font(DashFont.label(9))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
        }
        .disabled(attribution.legalURL == nil)
        .accessibilityLabel("Weather data by \(attribution.name)")
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: store.isLoading ? "cloud" : "cloud.slash")
                .font(.system(size: 24))
                .foregroundStyle(theme.secondaryText)
            Text(store.lastError ?? (store.isLoading ? "Checking…" : "Waiting for location"))
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }
}
