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

    /// Where a point falls relative to a line segment.
    public struct Projection: Hashable, Sendable {
        /// The nearest point on the segment.
        public let coordinate: Coordinate
        /// How far along the segment that point is, in metres.
        public let distanceAlongSegment: Double
        /// Perpendicular distance from the original point to the segment, in metres.
        /// This is the "how far off the road are we" number.
        public let crossTrackDistance: Double
        /// Position along the segment, clamped to 0...1.
        public let t: Double
    }

    /// Projects a point onto a segment.
    ///
    /// Uses a local equirectangular approximation — latitude and longitude converted to
    /// metres about the segment's start — rather than proper geodesics. Over the tens or
    /// hundreds of metres a route segment spans, the error is far below GPS noise, and
    /// the alternative costs several transcendental functions per segment on a path that
    /// runs for every location update.
    public static func project(
        _ point: Coordinate,
        onto start: Coordinate,
        _ end: Coordinate
    ) -> Projection {
        let metresPerDegreeLat = earthRadius * .pi / 180
        let metresPerDegreeLon = metresPerDegreeLat * cos(radians(start.latitude))

        let ax = 0.0, ay = 0.0
        let bx = (end.longitude - start.longitude) * metresPerDegreeLon
        let by = (end.latitude - start.latitude) * metresPerDegreeLat
        let px = (point.longitude - start.longitude) * metresPerDegreeLon
        let py = (point.latitude - start.latitude) * metresPerDegreeLat

        let abx = bx - ax, aby = by - ay
        let lengthSquared = abx * abx + aby * aby

        // A zero-length segment — duplicated points do occur in real route geometry.
        guard lengthSquared > 1e-9 else {
            return Projection(
                coordinate: start,
                distanceAlongSegment: 0,
                crossTrackDistance: sqrt(px * px + py * py),
                t: 0
            )
        }

        let rawT = (px * abx + py * aby) / lengthSquared
        let t = Swift.min(Swift.max(rawT, 0), 1)

        let projectedX = abx * t
        let projectedY = aby * t
        let dx = px - projectedX
        let dy = py - projectedY

        return Projection(
            coordinate: Coordinate(
                latitude: start.latitude + projectedY / metresPerDegreeLat,
                longitude: start.longitude + (metresPerDegreeLon == 0 ? 0 : projectedX / metresPerDegreeLon)
            ),
            distanceAlongSegment: t * sqrt(lengthSquared),
            crossTrackDistance: sqrt(dx * dx + dy * dy),
            t: t
        )
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
