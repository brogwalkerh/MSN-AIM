import Foundation
@testable import CarDashCore

/// Synthesised routes and drives.
///
/// Recorded traces would be more faithful, but a generated one can be shaped to hit the
/// exact cases that matter — a wrong turn at a known point, a single wild fix, a step
/// too short for its own prompt — which is what these tests are for.
enum TestRoute {
    static let origin = Coordinate(latitude: 51.5, longitude: -0.1)

    static func offset(_ from: Coordinate, north: Double = 0, east: Double = 0) -> Coordinate {
        let metresPerDegreeLat = GeoMath.earthRadius * .pi / 180
        let metresPerDegreeLon = metresPerDegreeLat * cos(GeoMath.radians(from.latitude))
        return Coordinate(
            latitude: from.latitude + north / metresPerDegreeLat,
            longitude: from.longitude + east / metresPerDegreeLon
        )
    }

    static func line(from start: Coordinate, to end: Coordinate, points: Int) -> [Coordinate] {
        (0...points).map { index in
            let t = Double(index) / Double(points)
            return Coordinate(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            )
        }
    }

    /// Three kilometres north, right turn, one kilometre east, arrive.
    ///
    /// The step lengths are chosen so the first step is long enough for a 2 km prompt
    /// and the second is not — which is the case the prompt-suppression logic exists for.
    static func lShaped() -> Route {
        let corner = offset(origin, north: 3000)
        let destination = offset(corner, east: 1000)

        let first = GuidanceStep(
            id: 0,
            instruction: "Head north on Long Road",
            distance: 3000,
            polyline: line(from: origin, to: corner, points: 15)
        )
        let second = GuidanceStep(
            id: 1,
            instruction: "Turn right onto East Street",
            distance: 1000,
            polyline: line(from: corner, to: destination, points: 8)
        )
        // Routers usually end with a near-zero-length "arrive" step.
        let arrive = GuidanceStep(
            id: 2,
            instruction: "Arrive at your destination",
            distance: 0,
            polyline: [destination]
        )

        return Route(
            name: "Test",
            steps: [first, second, arrive],
            totalDistance: 4000,
            expectedTravelTime: 4000 / 13
        )
    }

    /// Fixes sampled along a route at a fixed spacing and speed.
    static func drive(
        _ route: Route,
        spacing: Double = 50,
        speed: Double = 13,
        from start: Date = Date(timeIntervalSince1970: 1_767_225_600),
        accuracy: Double = 5
    ) -> [GeoFix] {
        let points = route.polyline
        guard points.count > 1 else { return [] }

        var fixes: [GeoFix] = []
        var travelled = 0.0
        var carry = 0.0

        for (a, b) in zip(points, points.dropFirst()) {
            let length = GeoMath.distance(from: a, to: b)
            guard length > 0 else { continue }
            let course = GeoMath.bearing(from: a, to: b)

            var along = carry
            while along < length {
                let t = along / length
                fixes.append(
                    GeoFix(
                        coordinate: Coordinate(
                            latitude: a.latitude + (b.latitude - a.latitude) * t,
                            longitude: a.longitude + (b.longitude - a.longitude) * t
                        ),
                        course: course,
                        speed: speed,
                        horizontalAccuracy: accuracy,
                        timestamp: start.addingTimeInterval((travelled + along) / speed)
                    )
                )
                along += spacing
            }
            carry = along - length
            travelled += length
        }

        if let last = points.last {
            fixes.append(
                GeoFix(
                    coordinate: last,
                    course: fixes.last?.course,
                    speed: speed,
                    horizontalAccuracy: accuracy,
                    timestamp: start.addingTimeInterval(travelled / speed)
                )
            )
        }
        return fixes
    }

    /// Replaces one fix with a wild one, the way a reflection off a building does.
    static func withGlitch(_ fixes: [GeoFix], at index: Int, metresEast: Double = 500) -> [GeoFix] {
        var result = fixes
        guard result.indices.contains(index) else { return result }
        let original = result[index]
        result[index] = GeoFix(
            coordinate: offset(original.coordinate, east: metresEast),
            course: original.course,
            speed: original.speed,
            horizontalAccuracy: original.horizontalAccuracy,
            timestamp: original.timestamp
        )
        return result
    }

    /// Everything from `index` onwards diverges east — a missed turn.
    static func withWrongTurn(_ fixes: [GeoFix], from index: Int) -> [GeoFix] {
        var result = fixes
        guard result.indices.contains(index) else { return result }
        for offsetIndex in index..<result.count {
            let drift = Double(offsetIndex - index + 1) * 25
            let original = result[offsetIndex]
            result[offsetIndex] = GeoFix(
                coordinate: offset(original.coordinate, east: drift),
                course: original.course,
                speed: original.speed,
                horizontalAccuracy: original.horizontalAccuracy,
                timestamp: original.timestamp
            )
        }
        return result
    }
}
