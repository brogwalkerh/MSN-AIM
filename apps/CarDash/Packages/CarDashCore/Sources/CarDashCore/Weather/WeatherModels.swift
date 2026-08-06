import Foundation

/// A sky condition, normalised away from any one provider's coding.
///
/// Sits between the API and the view so that swapping Open-Meteo for WeatherKit later
/// is a provider change and not a change to every view that renders weather.
public enum WeatherCondition: String, Hashable, Sendable, Codable, CaseIterable {
    case clear
    case mainlyClear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case freezingDrizzle
    case rain
    case freezingRain
    case snow
    case snowGrains
    case showers
    case snowShowers
    case thunderstorm
    case thunderstormWithHail
    case unknown

    /// Maps a WMO 4677 present-weather code, which is what Open-Meteo reports.
    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1: self = .mainlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61, 63, 65: self = .rain
        case 66, 67: self = .freezingRain
        case 71, 73, 75: self = .snow
        case 77: self = .snowGrains
        case 80, 81, 82: self = .showers
        case 85, 86: self = .snowShowers
        case 95: self = .thunderstorm
        case 96, 99: self = .thunderstormWithHail
        default: self = .unknown
        }
    }

    public var describedBriefly: String {
        switch self {
        case .clear: return "Clear"
        case .mainlyClear: return "Mainly clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .freezingDrizzle: return "Freezing drizzle"
        case .rain: return "Rain"
        case .freezingRain: return "Freezing rain"
        case .snow: return "Snow"
        case .snowGrains: return "Snow grains"
        case .showers: return "Showers"
        case .snowShowers: return "Snow showers"
        case .thunderstorm: return "Thunderstorms"
        case .thunderstormWithHail: return "Thunderstorms and hail"
        case .unknown: return "—"
        }
    }

    /// Conditions worth telling a driver about even though the tile is small.
    public var isHazardous: Bool {
        switch self {
        case .freezingDrizzle, .freezingRain, .snow, .snowGrains, .snowShowers,
             .thunderstorm, .thunderstormWithHail, .fog:
            return true
        default:
            return false
        }
    }
}

public struct CurrentConditions: Hashable, Sendable, Codable {
    public let time: Date
    /// Degrees Celsius. Converted for display; stored in one unit so caching and
    /// comparison do not depend on a user setting.
    public let temperature: Double
    public let apparentTemperature: Double
    public let condition: WeatherCondition
    /// Metres per second.
    public let windSpeed: Double
    public let isDaylight: Bool

    public init(
        time: Date,
        temperature: Double,
        apparentTemperature: Double,
        condition: WeatherCondition,
        windSpeed: Double,
        isDaylight: Bool
    ) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.windSpeed = windSpeed
        self.isDaylight = isDaylight
    }
}

public struct HourForecast: Hashable, Sendable, Codable, Identifiable {
    public var id: Date { time }
    public let time: Date
    public let temperature: Double
    /// 0...1, or nil when the provider does not supply one.
    public let precipitationProbability: Double?
    public let condition: WeatherCondition

    public init(
        time: Date,
        temperature: Double,
        precipitationProbability: Double?,
        condition: WeatherCondition
    ) {
        self.time = time
        self.temperature = temperature
        self.precipitationProbability = precipitationProbability
        self.condition = condition
    }
}

/// Who supplied the data, and where the licence says to point people.
///
/// Not optional, and not a detail. Both Open-Meteo (CC BY 4.0) and WeatherKit require
/// visible attribution, so the type makes it impossible to model a forecast that does
/// not carry one.
public struct WeatherAttribution: Hashable, Sendable, Codable {
    public let name: String
    public let legalURL: URL?

    public init(name: String, legalURL: URL?) {
        self.name = name
        self.legalURL = legalURL
    }

    public static let openMeteo = WeatherAttribution(
        name: "Open-Meteo",
        legalURL: URL(string: "https://open-meteo.com/en/license")
    )
}

public struct WeatherSnapshot: Hashable, Sendable, Codable {
    public let coordinate: Coordinate
    public let current: CurrentConditions
    public let hourly: [HourForecast]
    public let fetchedAt: Date
    public let attribution: WeatherAttribution

    public init(
        coordinate: Coordinate,
        current: CurrentConditions,
        hourly: [HourForecast],
        fetchedAt: Date,
        attribution: WeatherAttribution
    ) {
        self.coordinate = coordinate
        self.current = current
        self.hourly = hourly
        self.fetchedAt = fetchedAt
        self.attribution = attribution
    }

    public func isFresh(at date: Date, ttl: TimeInterval) -> Bool {
        date.timeIntervalSince(fetchedAt) < ttl
    }

    /// The next `count` hours from `date`, for the strip along the bottom of the tile.
    public func upcoming(from date: Date, count: Int) -> [HourForecast] {
        Array(hourly.filter { $0.time >= date }.prefix(count))
    }
}

public enum WeatherError: Error, Hashable, Sendable {
    case malformedResponse(String)
    case noCurrentConditions
    case requestFailed(status: Int)
}
