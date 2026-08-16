import CoreLocation
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

    /// A map item for a bare coordinate — somewhere with a position and no address.
    ///
    /// `MKMapItem(placemark:)` was the way to do this, and `MKPlacemark` went with it; both
    /// are deprecated as of iOS 26 in favour of a location and an optional `MKAddress`. Nil is
    /// the honest address here: this is the driver's own position, which is a fix rather than
    /// a place, and inventing a reverse-geocoded label for it would be a network round trip
    /// for something nothing displays.
    var mapItem: MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: latitude, longitude: longitude),
            address: nil
        )
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
