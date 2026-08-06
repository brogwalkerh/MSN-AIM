import Foundation
import Testing
@testable import CarDashCore

@Suite("Open-Meteo")
struct OpenMeteoDecoderTests {
    private let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    private let fetchedAt = Date(timeIntervalSince1970: 1_754_463_600)

    private func snapshot() throws -> WeatherSnapshot {
        try OpenMeteoDecoder.decode(
            try Fixture.data("open-meteo-london"),
            coordinate: london,
            fetchedAt: fetchedAt
        )
    }

    @Test("Current conditions decode, with WMO codes mapped")
    func current() throws {
        let current = try snapshot().current
        #expect(current.temperature == 18.3)
        #expect(current.apparentTemperature == 17.6)
        #expect(current.condition == .rain, "WMO 61 is moderate rain")
        #expect(current.windSpeed == 4.2)
        #expect(current.isDaylight)
        #expect(current.time == Date(timeIntervalSince1970: 1_754_463_600))
    }

    // The request asks for unixtime specifically, because Open-Meteo's default is a
    // naive local ISO string with no offset. This asserts the decoder is reading the
    // format the request actually asks for.
    @Test("Timestamps are read as epoch seconds")
    func timestamps() throws {
        let url = try #require(OpenMeteoDecoder.requestURL(for: london))
        let query = try #require(url.query)
        #expect(query.contains("timeformat=unixtime"))
        #expect(query.contains("wind_speed_unit=ms"), "so speeds match CoreLocation")

        let first = try #require(snapshot().hourly.first)
        #expect(first.time == Date(timeIntervalSince1970: 1_754_463_600))
    }

    @Test("The request asks for everything the decoder reads")
    func requestCoversFields() throws {
        let url = try #require(OpenMeteoDecoder.requestURL(for: london))
        let query = try #require(url.query?.removingPercentEncoding)
        for field in ["temperature_2m", "apparent_temperature", "is_day",
                      "weather_code", "wind_speed_10m", "precipitation_probability"] {
            #expect(query.contains(field), "request omits \(field)")
        }
    }

    // Open-Meteo puts nulls in the hourly arrays where a model has no value. An hour
    // with no temperature has nothing to render, so it is dropped rather than shown as
    // a gap — and crucially it must not shift the remaining hours' data.
    @Test("Hours with null temperatures are dropped without misaligning the rest")
    func nullsAreSkipped() throws {
        let hourly = try snapshot().hourly
        #expect(hourly.count == 3, "one of the four fixture hours has a null temperature")

        #expect(hourly[0].temperature == 18.3)
        #expect(hourly[0].precipitationProbability == 0.4)
        #expect(hourly[0].condition == .rain)

        #expect(hourly[1].temperature == 19.1)
        #expect(hourly[1].condition == .overcast)

        // The fourth raw hour, still carrying its own values rather than the third's.
        #expect(hourly[2].temperature == 20.4)
        #expect(hourly[2].precipitationProbability == 0.1)
        #expect(hourly[2].condition == .clear)
    }

    @Test("Precipitation probability is normalised to a fraction")
    func probabilityScale() throws {
        for hour in try snapshot().hourly {
            if let probability = hour.precipitationProbability {
                #expect(probability >= 0 && probability <= 1, "got \(probability)")
            }
        }
    }

    @Test("Attribution is always present")
    func attribution() throws {
        let attribution = try snapshot().attribution
        #expect(attribution.name == "Open-Meteo")
        #expect(attribution.legalURL != nil, "the CC BY licence requires a link")
    }

    @Test("A response with no current block is an error, not an empty forecast")
    func missingCurrent() {
        #expect(throws: WeatherError.noCurrentConditions) {
            try OpenMeteoDecoder.decode(Data("{}".utf8), coordinate: london, fetchedAt: fetchedAt)
        }
    }

    @Test("Garbage is reported as malformed")
    func garbage() {
        #expect(throws: (any Error).self) {
            try OpenMeteoDecoder.decode(Data("<html>".utf8), coordinate: london, fetchedAt: fetchedAt)
        }
    }

    @Test("Freshness is judged against the fetch time")
    func freshness() throws {
        let snapshot = try snapshot()
        #expect(snapshot.isFresh(at: fetchedAt.addingTimeInterval(300), ttl: 900))
        #expect(!snapshot.isFresh(at: fetchedAt.addingTimeInterval(1200), ttl: 900))
    }

    @Test("Upcoming hours start from now")
    func upcoming() throws {
        let snapshot = try snapshot()
        let later = Date(timeIntervalSince1970: 1_754_467_200)
        #expect(snapshot.upcoming(from: later, count: 5).count == 2)
        #expect(snapshot.upcoming(from: fetchedAt, count: 2).count == 2)
    }

    @Test("Every WMO code maps to something, and unknown codes do not crash")
    func wmoMapping() {
        #expect(WeatherCondition(wmoCode: 0) == .clear)
        #expect(WeatherCondition(wmoCode: 45) == .fog)
        #expect(WeatherCondition(wmoCode: 95) == .thunderstorm)
        #expect(WeatherCondition(wmoCode: -1) == .unknown)
        #expect(WeatherCondition(wmoCode: 12_345) == .unknown)

        // Conditions a driver should be warned about are flagged as such.
        #expect(WeatherCondition(wmoCode: 67).isHazardous, "freezing rain")
        #expect(WeatherCondition(wmoCode: 75).isHazardous, "heavy snow")
        #expect(!WeatherCondition(wmoCode: 1).isHazardous)
    }
}
