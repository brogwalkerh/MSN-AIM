import Foundation

/// Spherical geometry, in metres and degrees.
///
/// Pure, so the trip meter and (later) the guidance engine can be replayed against
/// recorded GPS traces on Linux instead of only being observable from a moving car.
public enum GeoMath {
    /// Mean Earth radius (IUGG). Good to a few parts in a thousand at driving scale,
    /// which is far better than consumer GPS.
    public static let earthRadius: Double = 6_371_008.8

    public static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    public static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Great-circle distance in metres.
    public static func distance(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = radians(from.latitude)
        let lat2 = radians(to.latitude)
        let dLat = lat2 - lat1
        let dLon = radians(to.longitude - from.longitude)

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Initial bearing in degrees, 0 = north, clockwise.
    public static func bearing(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = radians(from.latitude)
        let lat2 = radians(to.latitude)
        let dLon = radians(to.longitude - from.longitude)

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let result = degrees(atan2(y, x))
        return result < 0 ? result + 360 : result
    }

    /// Smallest signed angle between two headings, in degrees, within ±180.
    ///
    /// The naive subtraction is wrong across north: a turn from 350° to 10° is 20°
    /// right, not 340° left.
    public static func headingDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}
