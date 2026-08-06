import CoreLocation
import Observation
import CarDashCore
import os

/// The app's single source of position, speed and heading.
///
/// Uses `CLLocationUpdate.liveUpdates`, the modern async API: iterating it implicitly
/// holds a service session, so Core Location handles the authorization prompt rather
/// than this class managing a delegate and a permission state machine.
///
/// **Only "When In Use" is ever requested.** Background continuation while navigating
/// comes from a `CLBackgroundActivitySession` (Phase 3), which is the sanctioned way to
/// keep updates flowing without the "Always" prompt and its recurring
/// "…has been using your location" nags.
@MainActor
@Observable
public final class LocationService {
    public enum Status: Equatable, Sendable {
        case idle
        case running
        case denied
        case restricted
        case unavailable
    }

    public private(set) var status: Status = .idle
    public private(set) var coordinate: Coordinate?
    /// Metres per second, or nil when Core Location has no valid measurement. Nil is
    /// meaningfully different from zero and is propagated as such.
    public private(set) var speed: Double?
    /// Degrees. Nil below walking pace, where course is noise rather than direction.
    public private(set) var course: Double?
    public private(set) var altitude: Double?
    public private(set) var horizontalAccuracy: Double?
    public private(set) var updatedAt: Date?

    public private(set) var trip = TripMeter()
    public private(set) var isDriving = false

    @ObservationIgnored private var detector = DrivingDetector()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "location")

    /// Below this, `course` is not reported: a stationary phone's course reading spins.
    private static let minimumSpeedForCourse: Double = 1.5

    public init() {}

    public func start() {
        guard task == nil else { return }
        status = .running

        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    self.apply(update)
                }
            } catch {
                Self.log.error("location updates ended: \(error)")
                self?.status = .unavailable
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        status = .idle
        // Location has stopped, so nothing more will say the car parked. Assuming it
        // did is the safe reading — the alternative leaves the UI locked forever.
        detector.reset()
        isDriving = false
    }

    public func resetTrip() {
        trip.reset()
    }

    private func apply(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            status = .denied
            return
        }
        if update.authorizationRestricted {
            status = .restricted
            return
        }
        if update.locationUnavailable {
            status = .unavailable
            return
        }

        status = .running
        guard let location = update.location else { return }

        let now = location.timestamp
        let position = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        coordinate = position
        // Core Location signals "unknown" with a negative value for both of these, which
        // must not be shown as 0 m/s or a heading of due north.
        speed = location.speed >= 0 ? location.speed : nil
        altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        horizontalAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        course = (location.course >= 0 && (speed ?? 0) >= Self.minimumSpeedForCourse)
            ? location.course
            : nil
        updatedAt = now

        isDriving = detector.update(speed: speed, at: now)
        trip.record(
            coordinate: position,
            speed: speed,
            accuracy: horizontalAccuracy,
            at: now
        )
    }
}
