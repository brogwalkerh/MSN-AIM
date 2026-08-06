import Foundation

/// Turns a route plus a stream of position fixes into "where am I, what's next, and
/// should I say something".
///
/// MapKit supplies route *data* — geometry, step text, distances — and no guidance at
/// all: no map matching, no off-route detection, no prompt scheduling. That is what this
/// is. Being pure and Foundation-only means it can be replayed against recorded traces
/// on Linux, which is the only way any of this gets exercised without driving a car.
public struct GuidanceEngine: Sendable {
    public let route: Route
    public private(set) var state: GuidanceState?

    // MARK: - Tuning

    /// How far off the line counts as off-route. Generous, because a two-lane road plus
    /// consumer GPS error is easily 25 metres from the centreline.
    public var offRouteDistance: Double = 45
    /// Consecutive off-route fixes before it is believed. This is the difference between
    /// "a fix bounced off a building" and "we missed the turn", and it is why a single
    /// wild fix cannot trigger a reroute.
    public var offRouteFixesRequired = 4
    /// Within this distance of the destination, the journey is over.
    public var arrivalRadius: Double = 25
    /// Fallback when a fix carries no speed — the route's own average.
    private var fallbackSpeed: Double {
        route.expectedTravelTime > 0 ? route.totalDistance / route.expectedTravelTime : 13
    }

    // MARK: - Precomputed route geometry

    private struct Segment {
        let start: Coordinate
        let end: Coordinate
        let length: Double
        /// Distance from the route's origin to this segment's start.
        let cumulative: Double
        let stepIndex: Int
    }

    private let segments: [Segment]
    private let totalLength: Double
    /// Distance from the origin to the end of each step — where its manoeuvre happens.
    private let stepEndDistance: [Double]

    // MARK: - Running state

    private var lastSegmentIndex: Int?
    private var firedPrompts: Set<String> = []
    private var promptsPreparedForStep = -1
    private var offRouteStreak = 0

    public init(route: Route) {
        self.route = route

        var segments: [Segment] = []
        var cumulative = 0.0
        var stepEnds: [Double] = []

        for (stepIndex, step) in route.steps.enumerated() {
            // Steps returned by a router are contiguous, but the join is sometimes a
            // repeated point and sometimes a gap. Bridging it explicitly keeps the
            // cumulative distances honest either way.
            if let previousEnd = segments.last?.end, let first = step.polyline.first,
               previousEnd != first {
                let length = GeoMath.distance(from: previousEnd, to: first)
                segments.append(Segment(
                    start: previousEnd, end: first,
                    length: length, cumulative: cumulative, stepIndex: stepIndex
                ))
                cumulative += length
            }

            for pair in zip(step.polyline, step.polyline.dropFirst()) {
                let length = GeoMath.distance(from: pair.0, to: pair.1)
                guard length > 0 else { continue }
                segments.append(Segment(
                    start: pair.0, end: pair.1,
                    length: length, cumulative: cumulative, stepIndex: stepIndex
                ))
                cumulative += length
            }
            stepEnds.append(cumulative)
        }

        self.segments = segments
        self.totalLength = cumulative
        self.stepEndDistance = stepEnds
    }

    // MARK: - Updating

    /// Feeds in a fix and returns any prompts that became due.
    @discardableResult
    public mutating func update(with fix: GeoFix) -> [ManeuverPrompt] {
        guard !segments.isEmpty else { return [] }

        // A fix this bad says nothing useful, and letting it through would drag the
        // snapped position around and possibly trip the off-route counter.
        if let accuracy = fix.horizontalAccuracy, accuracy > 100 { return [] }

        guard let match = nearestPosition(to: fix.coordinate) else { return [] }
        lastSegmentIndex = match.segmentIndex

        let segment = segments[match.segmentIndex]
        let alongTrack = segment.cumulative + match.projection.distanceAlongSegment
        let stepIndex = segment.stepIndex

        // Off-route is a streak, never a single reading.
        if match.projection.crossTrackDistance > offRouteDistance {
            offRouteStreak += 1
        } else {
            offRouteStreak = 0
        }
        let confidence = offRouteFixesRequired > 0
            ? Swift.min(1, Double(offRouteStreak) / Double(offRouteFixesRequired))
            : 0

        let distanceRemaining = Swift.max(0, totalLength - alongTrack)
        let distanceToManeuver = Swift.max(0, (stepEndDistance[safe: stepIndex] ?? totalLength) - alongTrack)
        let speed = (fix.speed.flatMap { $0 > 1 ? $0 : nil }) ?? fallbackSpeed

        let newState = GuidanceState(
            currentStepIndex: stepIndex,
            distanceToManeuver: distanceToManeuver,
            distanceRemaining: distanceRemaining,
            estimatedTimeRemaining: speed > 0 ? distanceRemaining / speed : 0,
            snappedCoordinate: match.projection.coordinate,
            crossTrackDistance: match.projection.crossTrackDistance,
            offRouteConfidence: confidence,
            hasArrived: distanceRemaining <= arrivalRadius,
            currentInstruction: route.steps[safe: stepIndex]?.instruction,
            nextInstruction: route.steps[safe: stepIndex + 1]?.instruction
        )
        state = newState

        // While off route the instructions are about a road we are no longer on, so
        // saying them would be worse than saying nothing.
        guard !newState.isOffRoute else { return [] }
        return duePrompts(for: newState)
    }

    public mutating func reset() {
        state = nil
        lastSegmentIndex = nil
        firedPrompts.removeAll()
        promptsPreparedForStep = -1
        offRouteStreak = 0
    }

    // MARK: - Matching

    private struct Match {
        let segmentIndex: Int
        let projection: GeoMath.Projection
    }

    /// Finds the closest point on the route.
    ///
    /// Searched in a window around the last match rather than over the whole route: a
    /// long route has thousands of segments and this runs on every fix. The window also
    /// avoids a real correctness trap — on a route that doubles back, a global search
    /// can snap to the *return* leg while still on the outbound one.
    private func nearestPosition(to coordinate: Coordinate) -> Match? {
        let range: Range<Int>
        if let last = lastSegmentIndex {
            range = Swift.max(0, last - 8)..<Swift.min(segments.count, last + 80)
        } else {
            range = 0..<segments.count
        }

        guard let best = closest(to: coordinate, in: range) else { return nil }

        // Far outside the window: either a genuinely wild fix or the app resumed
        // somewhere else entirely. Re-search globally before concluding anything.
        if best.projection.crossTrackDistance > 250, lastSegmentIndex != nil {
            return closest(to: coordinate, in: 0..<segments.count) ?? best
        }
        return best
    }

    private func closest(to coordinate: Coordinate, in range: Range<Int>) -> Match? {
        var best: Match?
        for index in range {
            let segment = segments[index]
            let projection = GeoMath.project(coordinate, onto: segment.start, segment.end)
            if best == nil || projection.crossTrackDistance < best!.projection.crossTrackDistance {
                best = Match(segmentIndex: index, projection: projection)
            }
        }
        return best
    }

    // MARK: - Prompts

    private mutating func duePrompts(for state: GuidanceState) -> [ManeuverPrompt] {
        let stepIndex = state.currentStepIndex
        guard let step = route.steps[safe: stepIndex] else { return [] }

        // On entering a step, retire the triggers that can never fire meaningfully in
        // it. Without this, entering a 300-metre step immediately satisfies "distance to
        // manoeuvre is under 2 km" and announces "In 2 kilometres, turn left" — which is
        // both wrong and the kind of thing that makes people stop trusting the voice.
        if promptsPreparedForStep != stepIndex {
            promptsPreparedForStep = stepIndex
            for trigger in ManeuverPrompt.Trigger.allCases
            where trigger != .arrival && trigger.distance > step.distance * 0.95 {
                firedPrompts.insert("\(stepIndex)-\(trigger.rawValue)")
            }
        }

        var due: [ManeuverPrompt] = []

        for trigger in ManeuverPrompt.Trigger.allCases.sorted() {
            // Arrival is a property of the journey, not of a step, and is keyed
            // accordingly. Routers often end with a zero-length "arrive" step that no
            // fix ever matches, so tying arrival to being on the last step would mean it
            // never announced.
            let id: String
            if trigger == .arrival {
                guard state.hasArrived else { continue }
                id = "arrival"
            } else {
                guard state.distanceToManeuver <= trigger.distance else { continue }
                id = "\(stepIndex)-\(trigger.rawValue)"
            }

            guard !firedPrompts.contains(id) else { continue }
            firedPrompts.insert(id)

            due.append(
                ManeuverPrompt(
                    stepIndex: stepIndex,
                    trigger: trigger,
                    text: trigger == .arrival
                        ? "You have arrived."
                        : trigger.lead + step.instruction
                )
            )
        }

        return due
    }
}

extension Array {
    /// Bounds-checked lookup, for indices derived from route geometry where an
    /// off-by-one should degrade rather than trap.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
