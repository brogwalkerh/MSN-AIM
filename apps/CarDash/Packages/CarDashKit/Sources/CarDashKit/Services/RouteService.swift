import MapKit
import Observation
import CarDashCore
import os

/// Owns the current route: calculating it, following it, and deciding when to
/// recalculate.
@MainActor
@Observable
public final class RouteService {
    public enum Phase: Equatable {
        case idle
        case calculating
        case navigating
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var destinationName: String?
    public private(set) var routePolyline: [CLLocationCoordinate2D] = []
    public private(set) var guidance: GuidanceState?
    /// Set when a recalculation is wanted but the rate limit is holding it back, so the
    /// UI can say "off route" rather than silently doing nothing.
    public private(set) var isRerouting = false

    @ObservationIgnored private var engine: GuidanceEngine?
    @ObservationIgnored private var destination: MKMapItem?
    @ObservationIgnored private var lastRouteRequest: Date?
    @ObservationIgnored private var consecutiveThrottles = 0
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "route")

    /// MKDirections has an undocumented server-side quota and starts refusing requests
    /// when hammered. Recalculating at most twice a minute is well inside anything a
    /// driver would notice, and keeps a pathological off-route loop from burning it.
    private static let minimumRerouteInterval: TimeInterval = 30

    public init() {}

    // MARK: - Starting and stopping

    public func startNavigating(to item: MKMapItem, from origin: Coordinate) async {
        destination = item
        destinationName = item.name
        await calculate(from: origin)
    }

    public func stop() {
        phase = .idle
        engine = nil
        destination = nil
        destinationName = nil
        routePolyline = []
        guidance = nil
        isRerouting = false
        lastRouteRequest = nil
        consecutiveThrottles = 0
    }

    // MARK: - Following

    /// Feeds a fix to the guidance engine and returns anything that should be spoken.
    @discardableResult
    public func ingest(_ fix: GeoFix) -> [ManeuverPrompt] {
        guard var engine, phase == .navigating else { return [] }
        let prompts = engine.update(with: fix)
        self.engine = engine
        guidance = engine.state

        if engine.state?.isOffRoute == true {
            Task { await rerouteIfAllowed(from: fix.coordinate) }
        }
        return prompts
    }

    // MARK: - Calculating

    private func calculate(from origin: Coordinate) async {
        guard let destination else { return }

        phase = .calculating
        lastRouteRequest = Date()

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.clCoordinate))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                phase = .failed("No route found")
                return
            }

            routePolyline = route.polyline.coordinates
            engine = GuidanceEngine(route: route.asGuidanceRoute())
            guidance = nil
            phase = .navigating
            isRerouting = false
            consecutiveThrottles = 0
        } catch {
            // Throttling is a temporary condition and reads very differently from "there
            // is no road there" — the UI should say so rather than dropping the route.
            if (error as? MKError)?.code == .loadingThrottled {
                consecutiveThrottles += 1
                Self.log.notice("MKDirections throttled (\(self.consecutiveThrottles))")
                phase = engine == nil ? .failed("Routing busy — try again shortly") : .navigating
            } else {
                Self.log.error("route calculation failed: \(error)")
                phase = .failed(error.localizedDescription)
            }
            isRerouting = false
        }
    }

    private func rerouteIfAllowed(from origin: Coordinate) async {
        guard !isRerouting, destination != nil else { return }

        if let last = lastRouteRequest {
            // Back off harder each time the server pushes back, rather than retrying at
            // the same cadence into a quota that is already exhausted.
            let interval = Self.minimumRerouteInterval
                * pow(2, Double(min(consecutiveThrottles, 3)))
            guard Date().timeIntervalSince(last) >= interval else { return }
        }

        isRerouting = true
        await calculate(from: origin)
    }
}
