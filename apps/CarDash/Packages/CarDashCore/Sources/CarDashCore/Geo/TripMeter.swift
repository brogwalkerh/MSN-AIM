import Foundation

/// Distance and time for the current journey.
///
/// Consumer GPS is noisy in exactly the ways that break a naive odometer: a parked car
/// wanders by a few metres a second, and a lost-then-reacquired fix can teleport you
/// across town. Both would silently inflate the total, and the error only ever
/// accumulates upward. So fixes are filtered before they count.
public struct TripMeter: Hashable, Sendable, Codable {
    /// Metres travelled.
    public private(set) var distance: Double = 0
    /// Seconds spent actually moving — excludes time parked, so the average speed means
    /// something.
    public private(set) var movingTime: TimeInterval = 0
    /// Metres per second.
    public private(set) var maxSpeed: Double = 0
    public private(set) var startedAt: Date?

    private var lastCoordinate: Coordinate?
    private var lastTime: Date?

    /// Fixes worse than this are ignored entirely. Urban GPS routinely reports 30–65 m
    /// accuracy between buildings.
    public var accuracyLimit: Double = 50
    /// Movement below this between fixes is treated as noise, not travel. A stationary
    /// phone drifts a few metres a second.
    public var minimumStep: Double = 6
    /// ~325 km/h. Anything faster is a re-acquired fix jumping, not a car.
    public var implausibleSpeed: Double = 90

    public init() {}

    @discardableResult
    public mutating func record(
        coordinate: Coordinate,
        speed: Double?,
        accuracy: Double?,
        at time: Date
    ) -> Bool {
        guard coordinate.isValid else { return false }
        if let accuracy, accuracy < 0 || accuracy > accuracyLimit { return false }

        if let speed, speed >= 0, speed.isFinite {
            maxSpeed = Swift.max(maxSpeed, speed)
        }
        if startedAt == nil { startedAt = time }

        defer {
            lastCoordinate = coordinate
            lastTime = time
        }

        guard let previous = lastCoordinate, let previousTime = lastTime else { return false }

        let elapsed = time.timeIntervalSince(previousTime)
        guard elapsed > 0 else { return false }

        let step = GeoMath.distance(from: previous, to: coordinate)

        // Sitting still. Counting this is how a parked car accumulates a kilometre
        // overnight.
        guard step >= minimumStep else { return false }

        // A jump no car made — a fix re-acquired after a tunnel, say. Accepting it would
        // add the whole tunnel as travelled distance in a single step.
        guard step / elapsed <= implausibleSpeed else { return false }

        distance += step
        movingTime += elapsed
        return true
    }

    /// Metres per second, over moving time only.
    public var averageSpeed: Double {
        movingTime > 0 ? distance / movingTime : 0
    }

    public mutating func reset() {
        self = TripMeter()
    }
}
