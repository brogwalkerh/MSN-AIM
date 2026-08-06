import Foundation

/// Turns an Open-Meteo forecast response into a `WeatherSnapshot`.
///
/// Parsing lives in Core, away from the URLSession call in CarDashKit, so it can be
/// exercised against a committed fixture on Linux. Response parsing is where weather
/// integrations actually break — a renamed field, a null in an array — and that is
/// exactly the kind of failure that is otherwise only discovered in a car.
public enum OpenMeteoDecoder {
    /// The query this decoder expects. Kept beside the decoder so the two cannot drift.
    ///
    /// Two parameters are load-bearing:
    ///
    /// - `timeformat=unixtime` makes every timestamp an integer. The default is a
    ///   *naive local* ISO string with no offset, which is ambiguous and a reliable
    ///   source of off-by-an-hour bugs at the edges of daylight saving.
    /// - `wind_speed_unit=ms` matches CoreLocation, so nothing in the app has to
    ///   remember which speed is in which unit. Open-Meteo's default is km/h.
    public static func requestURL(for coordinate: Coordinate, forecastHours: Int = 12) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,precipitation_probability,weather_code"
            ),
            URLQueryItem(name: "forecast_hours", value: String(forecastHours)),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        return components?.url
    }

    public static func decode(
        _ data: Data,
        coordinate: Coordinate,
        fetchedAt: Date
    ) throws -> WeatherSnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WeatherError.malformedResponse("\(error)")
        }

        guard let current = response.current else {
            throw WeatherError.noCurrentConditions
        }

        let conditions = CurrentConditions(
            time: Date(timeIntervalSince1970: TimeInterval(current.time)),
            temperature: current.temperature_2m ?? .nan,
            apparentTemperature: current.apparent_temperature ?? current.temperature_2m ?? .nan,
            condition: WeatherCondition(wmoCode: current.weather_code ?? -1),
            windSpeed: current.wind_speed_10m ?? 0,
            isDaylight: (current.is_day ?? 1) == 1
        )

        guard conditions.temperature.isFinite else {
            throw WeatherError.malformedResponse("current temperature missing")
        }

        return WeatherSnapshot(
            coordinate: coordinate,
            current: conditions,
            hourly: hourly(from: response.hourly),
            fetchedAt: fetchedAt,
            attribution: .openMeteo
        )
    }

    private static func hourly(from block: Response.Hourly?) -> [HourForecast] {
        guard let block, let times = block.time else { return [] }

        let temperatures = block.temperature_2m ?? []
        let probabilities = block.precipitation_probability ?? []
        let codes = block.weather_code ?? []

        // The parallel arrays should be the same length. If a provider change ever makes
        // them differ, returning fewer hours is much better than trapping on an index.
        let count = Swift.min(times.count, temperatures.count)

        return (0..<count).compactMap { index -> HourForecast? in
            // An hour with a null temperature has nothing to show, so it is dropped
            // rather than rendered as a gap.
            guard let temperature = temperatures[index] else { return nil }

            let probability = index < probabilities.count ? probabilities[index] : nil
            let code = (index < codes.count ? codes[index] : nil) ?? -1

            return HourForecast(
                time: Date(timeIntervalSince1970: TimeInterval(times[index])),
                temperature: temperature,
                precipitationProbability: probability.map { Double($0) / 100 },
                condition: WeatherCondition(wmoCode: code)
            )
        }
    }

    // MARK: - Wire format

    // Every field is optional. Open-Meteo omits blocks it was not asked for and puts
    // nulls in arrays where a model has no value, so a struct of non-optionals would
    // fail to decode an otherwise usable forecast.
    private struct Response: Decodable {
        let current: Current?
        let hourly: Hourly?

        struct Current: Decodable {
            let time: Int
            let temperature_2m: Double?
            let apparent_temperature: Double?
            let is_day: Int?
            let weather_code: Int?
            let wind_speed_10m: Double?
        }

        struct Hourly: Decodable {
            let time: [Int]?
            let temperature_2m: [Double?]?
            let precipitation_probability: [Int?]?
            let weather_code: [Int?]?
        }
    }
}
