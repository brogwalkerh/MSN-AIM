import Foundation
import Testing
@testable import CarDashCore

@Suite("GeoMath")
struct GeoMathTests {
    private let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    private let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)

    @Test("Distance matches a known city pair")
    func knownDistance() {
        // London to Paris is about 344 km great-circle.
        let metres = GeoMath.distance(from: london, to: paris)
        #expect(metres > 340_000 && metres < 348_000, "got \(metres) m")
    }

    @Test("Distance is symmetric and zero for a point against itself")
    func distanceProperties() {
        #expect(GeoMath.distance(from: london, to: london) == 0)
        let there = GeoMath.distance(from: london, to: paris)
        let back = GeoMath.distance(from: paris, to: london)
        #expect(abs(there - back) < 0.001)
    }

    @Test("A degree of latitude is about 111 km anywhere")
    func latitudeDegree() {
        for latitude in [0.0, 30, 60, -45] {
            let a = Coordinate(latitude: latitude, longitude: 10)
            let b = Coordinate(latitude: latitude + 1, longitude: 10)
            let metres = GeoMath.distance(from: a, to: b)
            #expect(metres > 110_500 && metres < 111_500, "at \(latitude)° got \(metres) m")
        }
    }

    @Test("Bearings point the right way")
    func bearings() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        #expect(abs(GeoMath.bearing(from: origin, to: Coordinate(latitude: 1, longitude: 0)) - 0) < 0.5)
        #expect(abs(GeoMath.bearing(from: origin, to: Coordinate(latitude: 0, longitude: 1)) - 90) < 0.5)
        #expect(abs(GeoMath.bearing(from: origin, to: Coordinate(latitude: -1, longitude: 0)) - 180) < 0.5)
        #expect(abs(GeoMath.bearing(from: origin, to: Coordinate(latitude: 0, longitude: -1)) - 270) < 0.5)
    }

    // MARK: - Projection

    @Test("A point beside a segment projects onto it at the right offset")
    func projectionBesideSegment() {
        let start = Coordinate(latitude: 51.5, longitude: -0.1)
        let end = TestRoute.offset(start, north: 1000)
        // 300 m along, 40 m to the east of the line.
        let point = TestRoute.offset(TestRoute.offset(start, north: 300), east: 40)

        let projection = GeoMath.project(point, onto: start, end)
        #expect(abs(projection.distanceAlongSegment - 300) < 2)
        #expect(abs(projection.crossTrackDistance - 40) < 2)
        #expect(projection.t > 0.29 && projection.t < 0.31)
    }

    // Clamping matters: without it, a point beyond the end of a segment reports a
    // projection past the segment and the route position runs ahead of the car.
    @Test("A point past the end clamps to the end")
    func projectionClampsBeyondEnd() {
        let start = Coordinate(latitude: 51.5, longitude: -0.1)
        let end = TestRoute.offset(start, north: 100)
        let beyond = TestRoute.offset(start, north: 500)

        let projection = GeoMath.project(beyond, onto: start, end)
        #expect(projection.t == 1)
        #expect(abs(projection.distanceAlongSegment - 100) < 1)
        #expect(abs(projection.crossTrackDistance - 400) < 3, "distance to the segment's end")
    }

    @Test("A point before the start clamps to the start")
    func projectionClampsBeforeStart() {
        let start = Coordinate(latitude: 51.5, longitude: -0.1)
        let end = TestRoute.offset(start, north: 100)
        let before = TestRoute.offset(start, north: -50)

        let projection = GeoMath.project(before, onto: start, end)
        #expect(projection.t == 0)
        #expect(projection.distanceAlongSegment == 0)
        #expect(abs(projection.crossTrackDistance - 50) < 2)
    }

    @Test("A point on the segment has no cross-track error")
    func projectionOnTheLine() {
        let start = Coordinate(latitude: 51.5, longitude: -0.1)
        let end = TestRoute.offset(start, north: 800)
        let onLine = TestRoute.offset(start, north: 500)

        let projection = GeoMath.project(onLine, onto: start, end)
        #expect(projection.crossTrackDistance < 0.5)
        #expect(GeoMath.distance(from: projection.coordinate, to: onLine) < 0.5)
    }

    // Route geometry from a real router does contain repeated points.
    @Test("A zero-length segment does not divide by zero")
    func degenerateSegment() {
        let point = Coordinate(latitude: 51.5, longitude: -0.1)
        let projection = GeoMath.project(TestRoute.offset(point, east: 10), onto: point, point)

        #expect(projection.t == 0)
        #expect(projection.distanceAlongSegment == 0)
        #expect(abs(projection.crossTrackDistance - 10) < 1)
        #expect(projection.coordinate == point)
    }

    // The naive subtraction gets this wrong, and it is the calculation behind "are we
    // off route" and every rotating compass.
    @Test("Heading deltas take the short way round north")
    func headingWrapping() {
        #expect(GeoMath.headingDelta(from: 350, to: 10) == 20)
        #expect(GeoMath.headingDelta(from: 10, to: 350) == -20)
        #expect(GeoMath.headingDelta(from: 0, to: 180) == 180)
        #expect(GeoMath.headingDelta(from: 90, to: 80) == -10)
        #expect(abs(GeoMath.headingDelta(from: 359, to: 1)) == 2)
    }
}

@Suite("TripMeter")
struct TripMeterTests {
    private let start = Date(timeIntervalSince1970: 1_767_225_600)

    /// Roughly 111 metres north per 0.001° of latitude.
    private func north(_ steps: Int, from base: Double = 51.5) -> [Coordinate] {
        (0...steps).map { Coordinate(latitude: base + Double($0) * 0.001, longitude: -0.12) }
    }

    @Test("A straight drive accumulates about the right distance")
    func straightLine() {
        var meter = TripMeter()
        for (index, coordinate) in north(10).enumerated() {
            meter.record(
                coordinate: coordinate,
                speed: 20,
                accuracy: 5,
                at: start.addingTimeInterval(Double(index) * 5)
            )
        }
        // Ten steps of ~111 m.
        #expect(meter.distance > 1090 && meter.distance < 1130, "got \(meter.distance)")
        #expect(meter.movingTime == 50)
        #expect(meter.maxSpeed == 20)
    }

    // The failure this filter exists for: a car left parked with the app open should
    // read zero in the morning, not several kilometres of GPS wander.
    @Test("A parked car accumulates nothing")
    func parkedCarDoesNotDrift() {
        var meter = TripMeter()
        var generator = SeededGenerator(seed: 7)

        for second in 0..<600 {
            let jitter = Double.random(in: -0.00002...0.00002, using: &generator)
            meter.record(
                coordinate: Coordinate(latitude: 51.5 + jitter, longitude: -0.12 + jitter),
                speed: 0,
                accuracy: 8,
                at: start.addingTimeInterval(Double(second))
            )
        }
        #expect(meter.distance == 0, "drifted \(meter.distance) m while stationary")
    }

    @Test("A re-acquired fix after a tunnel is not counted as travel")
    func teleportIsRejected() {
        var meter = TripMeter()
        meter.record(coordinate: Coordinate(latitude: 51.5, longitude: -0.12),
                     speed: 20, accuracy: 5, at: start)
        meter.record(coordinate: Coordinate(latitude: 51.501, longitude: -0.12),
                     speed: 20, accuracy: 5, at: start.addingTimeInterval(5))
        let honest = meter.distance

        // 0.05° ≈ 5.5 km, one second later. No car did that.
        meter.record(coordinate: Coordinate(latitude: 51.551, longitude: -0.12),
                     speed: 20, accuracy: 5, at: start.addingTimeInterval(6))
        #expect(meter.distance == honest, "accepted an impossible jump")
    }

    @Test("Fixes with poor accuracy are ignored")
    func inaccurateFixesIgnored() {
        var meter = TripMeter()
        for (index, coordinate) in north(5).enumerated() {
            meter.record(
                coordinate: coordinate,
                speed: 20,
                accuracy: 400,
                at: start.addingTimeInterval(Double(index) * 5)
            )
        }
        #expect(meter.distance == 0)
    }

    @Test("Invalid coordinates are refused")
    func invalidCoordinates() {
        var meter = TripMeter()
        // Bound first: `#expect` cannot contain a mutating call.
        let accepted = meter.record(
            coordinate: Coordinate(latitude: 999, longitude: 0),
            speed: 10,
            accuracy: 5,
            at: start
        )
        #expect(!accepted)
        #expect(meter.distance == 0)
    }

    @Test("Average speed uses moving time, not wall-clock time")
    func averageExcludesStops() {
        var meter = TripMeter()
        meter.record(coordinate: Coordinate(latitude: 51.5, longitude: -0.12),
                     speed: 20, accuracy: 5, at: start)
        meter.record(coordinate: Coordinate(latitude: 51.501, longitude: -0.12),
                     speed: 20, accuracy: 5, at: start.addingTimeInterval(6))

        // An hour parked in between, contributing no distance and no moving time.
        meter.record(coordinate: Coordinate(latitude: 51.501, longitude: -0.12),
                     speed: 0, accuracy: 5, at: start.addingTimeInterval(3600))

        #expect(meter.movingTime == 6)
        #expect(meter.averageSpeed > 15, "an hour parked should not drag the average down")
    }

    @Test("Reset clears everything")
    func reset() {
        var meter = TripMeter()
        meter.record(coordinate: Coordinate(latitude: 51.5, longitude: -0.12),
                     speed: 30, accuracy: 5, at: start)
        meter.record(coordinate: Coordinate(latitude: 51.502, longitude: -0.12),
                     speed: 30, accuracy: 5, at: start.addingTimeInterval(10))
        meter.reset()

        #expect(meter.distance == 0)
        #expect(meter.movingTime == 0)
        #expect(meter.maxSpeed == 0)
        #expect(meter.startedAt == nil)
    }
}
