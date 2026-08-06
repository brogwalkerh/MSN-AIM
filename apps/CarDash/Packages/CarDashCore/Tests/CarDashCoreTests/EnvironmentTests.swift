import Foundation
import Testing
@testable import CarDashCore

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

private func hours(_ interval: TimeInterval) -> Double { interval / 3600 }

@Suite("SolarCalculator")
struct SolarCalculatorTests {
    private let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    private let sydney = Coordinate(latitude: -33.8688, longitude: 151.2093)
    private let tromso = Coordinate(latitude: 69.6496, longitude: 18.9560)
    private let quito = Coordinate(latitude: -0.1807, longitude: -78.4678)

    // A loose absolute check against a known almanac value. The tolerance is wide on
    // purpose — this exists to catch sign errors, a longitude convention flipped, or a
    // day-number off by one, not to certify the algorithm to the second.
    @Test("London at midsummer matches the almanac")
    func londonMidsummer() throws {
        let events = SolarCalculator.events(at: london, on: utc(2026, 6, 21))
        let sunrise = try #require(events.sunrise)
        let sunset = try #require(events.sunset)

        // Actual: 03:43 and 20:21 UTC.
        #expect(sunrise >= utc(2026, 6, 21, 3, 25) && sunrise <= utc(2026, 6, 21, 4, 0))
        #expect(sunset >= utc(2026, 6, 21, 20, 5) && sunset <= utc(2026, 6, 21, 20, 40))

        let length = hours(SolarCalculator.dayLength(at: london, on: utc(2026, 6, 21)))
        #expect(length > 16.2 && length < 17.0, "day length was \(length) hours")
    }

    @Test("The day is bracketed by sunrise and sunset", arguments: [
        utc(2026, 3, 20), utc(2026, 6, 21), utc(2026, 9, 22), utc(2026, 12, 21)
    ])
    func orderingHolds(day: Date) throws {
        let events = SolarCalculator.events(at: london, on: day)
        let sunrise = try #require(events.sunrise)
        let sunset = try #require(events.sunset)

        #expect(sunrise < events.transit)
        #expect(events.transit < sunset)
        #expect(SolarCalculator.isDaylight(at: london, on: events.transit))
        #expect(!SolarCalculator.isDaylight(at: london, on: events.transit.addingTimeInterval(-12 * 3600)))
    }

    @Test("Seasons run opposite ways in the two hemispheres")
    func hemispheresAreOpposite() {
        let june = utc(2026, 6, 21)
        let december = utc(2026, 12, 21)

        let londonJune = SolarCalculator.dayLength(at: london, on: june)
        let londonDecember = SolarCalculator.dayLength(at: london, on: december)
        let sydneyJune = SolarCalculator.dayLength(at: sydney, on: june)
        let sydneyDecember = SolarCalculator.dayLength(at: sydney, on: december)

        #expect(londonJune > londonDecember)
        #expect(sydneyDecember > sydneyJune)
    }

    @Test("On the equator the day is about twelve hours all year", arguments: [
        utc(2026, 1, 15), utc(2026, 4, 15), utc(2026, 7, 15), utc(2026, 10, 15)
    ])
    func equatorIsSteady(day: Date) {
        let length = hours(SolarCalculator.dayLength(at: quito, on: day))
        #expect(length > 11.7 && length < 12.5, "equator day length was \(length) hours")
    }

    // The case a naive implementation gets wrong by taking acos of something outside
    // [-1, 1] and producing NaN — which would silently make the theme calculation
    // useless above the arctic circle.
    @Test("Inside the arctic circle the sun may not rise or set at all")
    func polarDayAndNight() {
        let midsummer = SolarCalculator.events(at: tromso, on: utc(2026, 6, 21))
        #expect(midsummer.isPolarDay)
        #expect(midsummer.sunrise == nil)
        #expect(midsummer.sunset == nil)
        #expect(SolarCalculator.isDaylight(at: tromso, on: utc(2026, 6, 21, 2)))
        #expect(hours(SolarCalculator.dayLength(at: tromso, on: utc(2026, 6, 21))) == 24)

        let midwinter = SolarCalculator.events(at: tromso, on: utc(2026, 12, 21))
        #expect(midwinter.isPolarNight)
        #expect(!SolarCalculator.isDaylight(at: tromso, on: utc(2026, 12, 21, 12)))
        #expect(SolarCalculator.dayLength(at: tromso, on: utc(2026, 12, 21)) == 0)
    }

    // The textbook formulation assumes a midnight input and returns the following day's
    // events for anything later. Callers here pass "now", so every hour of the day must
    // resolve to the same day's sunrise.
    @Test("Any time of day resolves to that day's events", arguments: [0, 6, 12, 18, 23])
    func inputHourDoesNotShiftTheDay(hour: Int) throws {
        let reference = try #require(SolarCalculator.events(at: london, on: utc(2026, 6, 21, 0)).sunrise)
        let atHour = try #require(SolarCalculator.events(at: london, on: utc(2026, 6, 21, hour)).sunrise)
        #expect(abs(atHour.timeIntervalSince(reference)) < 120, "hour \(hour) shifted the result")
    }
}

@Suite("DrivingDetector")
struct DrivingDetectorTests {
    private let start = Date(timeIntervalSince1970: 1_767_225_600)

    @Test("Starts parked, and moving off is immediate")
    func becomesDrivingAtOnce() {
        var detector = DrivingDetector()
        #expect(!detector.isDriving)
        #expect(detector.update(speed: 5, at: start))
    }

    @Test("Walking pace does not count as driving")
    func walkingIsNotDriving() {
        var detector = DrivingDetector()
        #expect(!detector.update(speed: 1.4, at: start))
    }

    // The behaviour the hysteresis exists for. Stopping at a red light must not unlock
    // the layout editor and re-enable text fields for twenty seconds.
    @Test("A stop at a traffic light does not count as parking")
    func redLightStaysDriving() {
        var detector = DrivingDetector()
        _ = detector.update(speed: 12, at: start)

        for second in stride(from: 1.0, through: 10.0, by: 1.0) {
            #expect(detector.update(speed: 0, at: start.addingTimeInterval(second)),
                    "unlocked after only \(second)s stopped")
        }
    }

    @Test("Staying stopped long enough does count as parking")
    func parkingIsDetected() {
        var detector = DrivingDetector()
        _ = detector.update(speed: 12, at: start)
        _ = detector.update(speed: 0, at: start.addingTimeInterval(1))
        #expect(!detector.update(speed: 0, at: start.addingTimeInterval(30)))
    }

    @Test("Moving again resets the parking timer")
    func movingAgainCancelsTheStop() {
        var detector = DrivingDetector()
        _ = detector.update(speed: 12, at: start)
        _ = detector.update(speed: 0, at: start.addingTimeInterval(1))
        _ = detector.update(speed: 9, at: start.addingTimeInterval(5))
        #expect(detector.update(speed: 0, at: start.addingTimeInterval(10)))
    }

    // CoreLocation reports a negative speed when it has no valid measurement. Treating
    // that as "stationary" would unlock the controls on a motorway the moment the car
    // goes under a bridge.
    @Test("An unknown speed is not a report of being stationary", arguments: [nil, -1.0])
    func unknownSpeedHoldsState(speed: Double?) {
        var detector = DrivingDetector()
        _ = detector.update(speed: 20, at: start)
        #expect(detector.update(speed: speed, at: start.addingTimeInterval(60)))
        #expect(detector.update(speed: speed, at: start.addingTimeInterval(600)))
    }

    @Test("Reset returns to parked")
    func resetClearsState() {
        var detector = DrivingDetector()
        _ = detector.update(speed: 20, at: start)
        detector.reset()
        #expect(!detector.isDriving)
    }
}

@Suite("UnitFormatting")
struct UnitFormattingTests {
    @Test("Speed converts and rounds rather than truncating")
    func speed() {
        #expect(UnitFormatting.speedValue(metersPerSecond: 0, system: .metric) == 0)
        #expect(UnitFormatting.speedValue(metersPerSecond: 16.6, system: .metric) == 60)
        #expect(UnitFormatting.speedValue(metersPerSecond: 26.8, system: .imperial) == 60)
        // 59.7 km/h displayed as 59 would look like a broken speedometer.
        #expect(UnitFormatting.speedValue(metersPerSecond: 16.58, system: .metric) == 60)
    }

    @Test("An unknown speed is nil, not zero", arguments: [nil, -1.0, Double.nan, Double.infinity])
    func unknownSpeed(value: Double?) {
        #expect(UnitFormatting.speedValue(metersPerSecond: value, system: .metric) == nil)
    }

    @Test("Distance changes precision with magnitude")
    func distance() {
        #expect(UnitFormatting.distance(meters: 0, system: .metric) == "0 m")
        #expect(UnitFormatting.distance(meters: 412, system: .metric) == "410 m")
        #expect(UnitFormatting.distance(meters: 2400, system: .metric) == "2.4 km")
        #expect(UnitFormatting.distance(meters: 148_000, system: .metric) == "148 km")
        #expect(UnitFormatting.distance(meters: 30, system: .imperial) == "100 ft")
        #expect(UnitFormatting.distance(meters: 8047, system: .imperial) == "5.0 mi")
    }

    @Test("Durations read the way a driver says them")
    func duration() {
        #expect(UnitFormatting.duration(seconds: 480) == "8 min")
        #expect(UnitFormatting.duration(seconds: 5040) == "1 hr 24 min")
        #expect(UnitFormatting.duration(seconds: 7200) == "2 hr")
        // Never "0 min" for a route that still has some way to go.
        #expect(UnitFormatting.duration(seconds: 5) == "1 min")
    }

    @Test("Compass points wrap correctly")
    func compass() {
        #expect(UnitFormatting.compassPoint(degrees: 0) == "N")
        #expect(UnitFormatting.compassPoint(degrees: 90) == "E")
        #expect(UnitFormatting.compassPoint(degrees: 181) == "S")
        #expect(UnitFormatting.compassPoint(degrees: 359) == "N")
        #expect(UnitFormatting.compassPoint(degrees: 360) == "N")
        #expect(UnitFormatting.compassPoint(degrees: -90) == "W")
    }

    @Test("Temperature converts")
    func temperature() {
        #expect(UnitFormatting.temperature(celsius: 0, system: .metric) == "0°")
        #expect(UnitFormatting.temperature(celsius: 100, system: .imperial) == "212°")
        #expect(UnitFormatting.temperature(celsius: 18.6, system: .metric) == "19°")
    }
}

@Suite("Coordinate")
struct CoordinateTests {
    @Test("Rounding to a cache key collapses nearby positions")
    func rounding() {
        let a = Coordinate(latitude: 51.50741, longitude: -0.12776).rounded()
        let b = Coordinate(latitude: 51.50820, longitude: -0.12810).rounded()
        #expect(a == b, "positions a few hundred metres apart should share a cache key")

        let far = Coordinate(latitude: 51.60, longitude: -0.12).rounded()
        #expect(a != far)
    }

    @Test("Out-of-range coordinates are rejected")
    func validity() {
        #expect(Coordinate(latitude: 51, longitude: -0.1).isValid)
        #expect(!Coordinate(latitude: 91, longitude: 0).isValid)
        #expect(!Coordinate(latitude: 0, longitude: 181).isValid)
        #expect(!Coordinate(latitude: .nan, longitude: 0).isValid)
    }
}
