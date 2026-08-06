import MapKit
import CarDashCore

// Core speaks in its own `Coordinate` so it can be tested on Linux. This is the only
// place it meets CoreLocation and MapKit.

extension Coordinate {
    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}

extension MKRoute {
    /// Converts a MapKit route into the pure model the guidance engine works on.
    ///
    /// Steps with no geometry are dropped rather than kept: MapKit emits a zero-length
    /// "arrive" step, and a step with an empty polyline contributes nothing to route
    /// matching while making every index harder to reason about.
    func asGuidanceRoute() -> CarDashCore.Route {
        var steps: [GuidanceStep] = []
        for (index, step) in self.steps.enumerated() {
            let points = step.polyline.coordinates.map(Coordinate.init)
            guard !points.isEmpty else { continue }
            steps.append(
                GuidanceStep(
                    id: index,
                    instruction: step.instructions.isEmpty ? "Continue" : step.instructions,
                    notice: step.notice,
                    distance: step.distance,
                    polyline: points
                )
            )
        }

        return CarDashCore.Route(
            name: name,
            steps: steps,
            totalDistance: distance,
            expectedTravelTime: expectedTravelTime
        )
    }
}
