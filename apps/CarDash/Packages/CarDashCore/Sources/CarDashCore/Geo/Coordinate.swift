import Foundation

/// A position on the globe, in degrees.
///
/// Stands in for `CLLocationCoordinate2D`, which does not exist on Linux. Everything
/// that reasons about position — the guidance engine, the solar calculator, weather
/// cache keys — works in these so it can be tested without a device.
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
            && latitude.isFinite && longitude.isFinite
    }

    /// Rounded to roughly a kilometre.
    ///
    /// Used as the weather cache key. Without it, driving at 60 mph would invalidate the
    /// cache on every GPS fix and hammer the API for a forecast that is identical.
    public func rounded(toDegrees precision: Double = 0.01) -> Coordinate {
        Coordinate(
            latitude: (latitude / precision).rounded() * precision,
            longitude: (longitude / precision).rounded() * precision
        )
    }

    // A few places that are useful as defaults and in tests.
    public static let greenwich = Coordinate(latitude: 51.4779, longitude: -0.0015)
    public static let equator = Coordinate(latitude: 0, longitude: 0)
}
