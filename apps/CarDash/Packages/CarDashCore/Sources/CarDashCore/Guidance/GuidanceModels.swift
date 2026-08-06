import Foundation

/// One position report. The engine's only input.
///
/// Deliberately not a `CLLocation`: the guidance engine is replayed against recorded and
/// synthesised traces on Linux, where CoreLocation does not exist.
public struct GeoFix: Hashable, Sendable, Codable {
    public let coordinate: Coordinate
    /// Degrees, or nil below the speed at which course is meaningful.
    public let course: Double?
    /// Metres per second, or nil when unknown.
    public let speed: Double?
    /// Metres, or nil when unknown.
    public let horizontalAccuracy: Double?
    public let timestamp: Date

    public init(
        coordinate: Coordinate,
        course: Double? = nil,
        speed: Double? = nil,
        horizontalAccuracy: Double? = nil,
        timestamp: Date
    ) {
        self.coordinate = coordinate
        self.course = course
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

/// One leg of a route, up to and including its manoeuvre.
///
/// Mirrors what `MKRoute.Step` supplies — MapKit gives instruction text, distance and
/// geometry, and nothing else. Everything in `GuidanceEngine` is built from these three
/// things, which is the honest boundary of what MapKit-based navigation can do.
public struct GuidanceStep: Hashable, Sendable, Codable, Identifiable {
    public let id: Int
    /// e.g. "Turn left onto Gower Street".
    public let instruction: String
    /// Advisory text such as a toll road warning, when the router supplies one.
    public let notice: String?
    /// Length of this step in metres.
    public let distance: Double
    /// The step's geometry, start to end.
    public let polyline: [Coordinate]

    public init(
        id: Int,
        instruction: String,
        notice: String? = nil,
        distance: Double,
        polyline: [Coordinate]
    ) {
        self.id = id
        self.instruction = instruction
        self.notice = notice
        self.distance = distance
        self.polyline = polyline
    }
}

public struct Route: Hashable, Sendable, Codable {
    public let name: String
    public let steps: [GuidanceStep]
    public let totalDistance: Double
    public let expectedTravelTime: TimeInterval

    public init(
        name: String,
        steps: [GuidanceStep],
        totalDistance: Double,
        expectedTravelTime: TimeInterval
    ) {
        self.name = name
        self.steps = steps
        self.totalDistance = totalDistance
        self.expectedTravelTime = expectedTravelTime
    }

    /// The whole route as one list of points, with the duplicate joins between steps
    /// removed.
    public var polyline: [Coordinate] {
        var result: [Coordinate] = []
        for step in steps {
            for point in step.polyline where result.last != point {
                result.append(point)
            }
        }
        return result
    }
}

public struct GuidanceState: Hashable, Sendable {
    public var currentStepIndex: Int
    /// Metres to the end of the current step — where the manoeuvre happens.
    public var distanceToManeuver: Double
    /// Metres to the destination.
    public var distanceRemaining: Double
    public var estimatedTimeRemaining: TimeInterval
    /// The fix pulled onto the route, which is what the map should draw.
    public var snappedCoordinate: Coordinate
    /// Perpendicular distance from the route, in metres.
    public var crossTrackDistance: Double
    /// 0 when confidently on route, 1 when confidently off it. A ratio rather than a
    /// flag so the UI can show doubt before acting on it.
    public var offRouteConfidence: Double
    public var hasArrived: Bool

    public var isOffRoute: Bool { offRouteConfidence >= 1 }

    public var currentInstruction: String?
    public var nextInstruction: String?
}

/// A spoken or displayed cue for an upcoming manoeuvre.
public struct ManeuverPrompt: Hashable, Sendable, Identifiable {
    public enum Trigger: String, Sendable, Codable, CaseIterable, Comparable {
        case twoKilometres
        case fiveHundredMetres
        case oneHundredMetres
        case now
        case arrival

        /// Metres before the manoeuvre at which this fires.
        public var distance: Double {
            switch self {
            case .twoKilometres: return 2000
            case .fiveHundredMetres: return 500
            case .oneHundredMetres: return 100
            case .now: return 25
            case .arrival: return 0
            }
        }

        var lead: String {
            switch self {
            case .twoKilometres: return "In 2 kilometres, "
            case .fiveHundredMetres: return "In 500 metres, "
            case .oneHundredMetres: return "In 100 metres, "
            case .now, .arrival: return ""
            }
        }

        public static func < (lhs: Trigger, rhs: Trigger) -> Bool {
            lhs.distance > rhs.distance
        }
    }

    public var id: String { "\(stepIndex)-\(trigger.rawValue)" }
    public let stepIndex: Int
    public let trigger: Trigger
    /// Ready to speak.
    public let text: String
}
