import Foundation

/// Sunrise and sunset from a date and a position.
///
/// The dashboard switches between its day and night appearance on this rather than on
/// the system's light/dark setting, because the relevant question in a car is whether it
/// is dark outside — not what the user picked in Settings six months ago.
///
/// It is arithmetic rather than an API call for two reasons: it works with no signal, in
/// a tunnel or out of coverage, and it can be tested on Linux against known values. The
/// implementation is the standard NOAA/Wikipedia sunrise equation, accurate to a couple
/// of minutes, which is far beyond what "should the screen be dimmer" requires.
public enum SolarCalculator {
    public struct Events: Hashable, Sendable {
        /// Nil inside the polar circles when the sun does not cross the horizon.
        public let sunrise: Date?
        public let sunset: Date?
        /// Solar noon, which always exists.
        public let transit: Date
        /// True when the sun is up for the entire day (nil sunrise/sunset, polar day).
        public let isPolarDay: Bool
        public let isPolarNight: Bool
    }

    /// Refraction-corrected horizon: the sun's disc appears above the horizon slightly
    /// before it geometrically is.
    private static let horizonAngle = -0.833

    private static let obliquity = 23.4397

    public static func events(at coordinate: Coordinate, on date: Date) -> Events {
        let julian = julianDate(from: date)

        // Days since J2000. The textbook formulation uses ceil() here, which assumes the
        // input is at midnight — hand it a date at noon and it returns the *following*
        // day's sunrise. Rounding instead maps any instant within a UTC day to that
        // day's number, so callers can pass "now" without thinking about it.
        let n = (julian - 2_451_545.0 + 0.0008).rounded()
        let meanSolarTime = n - (-coordinate.longitude / 360)

        let meanAnomaly = (357.5291 + 0.98560028 * meanSolarTime)
            .truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(radians(meanAnomaly))
            + 0.0200 * sin(radians(2 * meanAnomaly))
            + 0.0003 * sin(radians(3 * meanAnomaly))
        let eclipticLongitude = (meanAnomaly + center + 180 + 102.9372)
            .truncatingRemainder(dividingBy: 360)

        let transitJulian = 2_451_545.0 + meanSolarTime
            + 0.0053 * sin(radians(meanAnomaly))
            - 0.0069 * sin(radians(2 * eclipticLongitude))

        let declination = asin(sin(radians(eclipticLongitude)) * sin(radians(obliquity)))
        let latitude = radians(coordinate.latitude)

        let cosHourAngle = (sin(radians(horizonAngle)) - sin(latitude) * sin(declination))
            / (cos(latitude) * cos(declination))

        let transit = instant(fromJulian: transitJulian)

        // Above the arctic or below the antarctic circle the sun may never rise or never
        // set. The sign of the impossible cosine says which.
        guard cosHourAngle >= -1, cosHourAngle <= 1 else {
            let polarDay = cosHourAngle < -1
            return Events(
                sunrise: nil,
                sunset: nil,
                transit: transit,
                isPolarDay: polarDay,
                isPolarNight: !polarDay
            )
        }

        let hourAngle = degrees(acos(cosHourAngle))
        return Events(
            sunrise: instant(fromJulian: transitJulian - hourAngle / 360),
            sunset: instant(fromJulian: transitJulian + hourAngle / 360),
            transit: transit,
            isPolarDay: false,
            isPolarNight: false
        )
    }

    /// Whether the sun is above the horizon.
    public static func isDaylight(at coordinate: Coordinate, on date: Date) -> Bool {
        let events = events(at: coordinate, on: date)
        if events.isPolarDay { return true }
        if events.isPolarNight { return false }
        guard let sunrise = events.sunrise, let sunset = events.sunset else { return true }
        return date >= sunrise && date <= sunset
    }

    /// How long the sun is up. Zero during polar night, 24 hours during polar day.
    public static func dayLength(at coordinate: Coordinate, on date: Date) -> TimeInterval {
        let events = events(at: coordinate, on: date)
        if events.isPolarDay { return 86_400 }
        if events.isPolarNight { return 0 }
        guard let sunrise = events.sunrise, let sunset = events.sunset else { return 0 }
        return sunset.timeIntervalSince(sunrise)
    }

    // MARK: - Conversions

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    private static func julianDate(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func instant(fromJulian julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86_400)
    }
}
