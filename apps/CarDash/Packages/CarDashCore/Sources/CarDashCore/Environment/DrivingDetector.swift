import Foundation

/// Decides whether the car is moving.
///
/// This gates real behaviour — while driving, text fields refuse focus and the layout
/// editor is disabled entirely — so it needs to be steady rather than merely correct.
/// A naive threshold flickers at walking pace and at traffic lights, and a dashboard
/// that keeps locking and unlocking its controls at every junction is worse than one
/// that is simply always locked.
///
/// Two mechanisms provide that steadiness: separate start and stop thresholds, and a
/// dwell time before "stopped" is believed. Nothing waits to *become* driving — the
/// moment the car is moving, the safety behaviour applies.
public struct DrivingDetector: Hashable, Sendable {
    /// ~8 km/h. Above walking pace, below any real road speed.
    public var startSpeed: Double = 2.2
    /// ~3 km/h. Deliberately lower than `startSpeed`; the gap is the hysteresis.
    public var stopSpeed: Double = 0.9
    /// How long the car must stay slow before it counts as stopped. Long enough to sit
    /// through a red light without the controls unlocking.
    public var stopDwell: TimeInterval = 12

    public private(set) var isDriving = false
    private var slowSince: Date?

    public init() {}

    /// Feeds in a new speed reading.
    ///
    /// - Parameter speed: metres per second, or nil when unknown. CoreLocation reports a
    ///   negative speed when it has no valid measurement; that is *not* a report of
    ///   being stationary, so it must not be treated as one — losing GPS under a bridge
    ///   should not unlock the editor mid-motorway.
    @discardableResult
    public mutating func update(speed: Double?, at time: Date) -> Bool {
        guard let speed, speed >= 0, speed.isFinite else { return isDriving }

        if speed >= startSpeed {
            isDriving = true
            slowSince = nil
            return isDriving
        }

        guard isDriving else {
            slowSince = nil
            return isDriving
        }

        if speed <= stopSpeed {
            if let since = slowSince {
                if time.timeIntervalSince(since) >= stopDwell {
                    isDriving = false
                    slowSince = nil
                }
            } else {
                slowSince = time
            }
        } else {
            // Between the two thresholds: still moving, just slowly. Neither confirms
            // stopping nor resets the clock — crawling in traffic should eventually
            // count as stopped if it stays below the start threshold.
            if slowSince == nil { slowSince = time }
        }

        return isDriving
    }

    /// Used when location updates stop entirely — backgrounding, or permission revoked.
    public mutating func reset() {
        isDriving = false
        slowSince = nil
    }
}
