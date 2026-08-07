import Foundation

/// What the lock screen shows while a route is running.
///
/// This exists because of a limitation stated plainly in the app's own settings sheet: when the
/// phone locks, the dashboard is gone. Audio and navigation keep running, but the screen the
/// driver was using does not — and a phone in a windscreen mount locks constantly.
///
/// It lives in `CarDashCore` and holds no ActivityKit types, so the presentation decisions — the
/// manoeuvre icon, the distance text, the arrival clock time — are proved on Linux. The
/// `ActivityAttributes` conformance is a one-line declaration in the iOS-only package that owns
/// the widget, which keeps the untestable part down to something with nothing in it to get
/// wrong.
///
/// Every field is a rendered string or a plain number rather than a formatter input, because a
/// Live Activity's content state crosses a process boundary into the widget extension: whatever
/// is not decided here has to be decided there, where none of it is testable.
public struct NavigationActivityState: Codable, Hashable, Sendable {
    /// "Turn right onto High Street".
    public var instruction: String
    /// SF Symbol for the manoeuvre, derived from the instruction text.
    public var maneuverSymbol: String
    /// "400 m", already in the user's units.
    public var distanceToManeuver: String
    /// "12 km", already in the user's units.
    public var distanceRemaining: String
    /// Seconds. Kept numeric so the widget can render a live-counting timer rather than a
    /// string that would freeze between updates.
    public var secondsRemaining: TimeInterval
    /// Where the arrival countdown lands, for a widget that prefers a clock to a duration.
    public var arrivalDate: Date
    public var hasArrived: Bool

    public init(
        instruction: String,
        maneuverSymbol: String,
        distanceToManeuver: String,
        distanceRemaining: String,
        secondsRemaining: TimeInterval,
        arrivalDate: Date,
        hasArrived: Bool
    ) {
        self.instruction = instruction
        self.maneuverSymbol = maneuverSymbol
        self.distanceToManeuver = distanceToManeuver
        self.distanceRemaining = distanceRemaining
        self.secondsRemaining = secondsRemaining
        self.arrivalDate = arrivalDate
        self.hasArrived = hasArrived
    }

    /// Builds the lock-screen state from what the guidance engine knows.
    ///
    /// - Parameter now: injected so the arrival date is testable rather than clock-dependent.
    public static func from(
        _ guidance: GuidanceState,
        units: UnitSystem,
        now: Date
    ) -> NavigationActivityState {
        let instruction = guidance.hasArrived
            ? "You have arrived"
            : (guidance.currentInstruction ?? "Continue")

        // A negative or non-finite time would make the widget's countdown run backwards or
        // refuse to render; the guidance engine can produce both from a stationary car.
        let seconds = guidance.estimatedTimeRemaining.isFinite
            ? max(0, guidance.estimatedTimeRemaining)
            : 0

        return NavigationActivityState(
            instruction: instruction,
            maneuverSymbol: ManeuverIcon.symbol(for: guidance.currentInstruction, hasArrived: guidance.hasArrived),
            distanceToManeuver: UnitFormatting.distance(meters: guidance.distanceToManeuver, system: units),
            distanceRemaining: UnitFormatting.distance(meters: guidance.distanceRemaining, system: units),
            secondsRemaining: seconds,
            arrivalDate: now.addingTimeInterval(seconds),
            hasArrived: guidance.hasArrived
        )
    }
}

/// Picks an arrow for a manoeuvre.
///
/// MapKit gives instruction *text* and nothing else — there is no manoeuvre type, no turn angle,
/// no exit number in `MKRoute.Step`. So the icon is inferred from the words, which is a
/// heuristic and is treated as one: anything unrecognised falls back to "continue straight"
/// rather than guessing a direction. A wrong arrow on a lock screen is worse than a neutral one,
/// because the driver may act on it without reading the text.
///
/// Order matters in the matching below, and that is the substance of this type: "turn left" and
/// "keep left" and "make a U-turn" all contain "left".
public enum ManeuverIcon {
    public static let fallback = "arrow.up"
    public static let arrived = "flag.checkered"

    public static func symbol(for instruction: String?, hasArrived: Bool = false) -> String {
        guard !hasArrived else { return arrived }
        guard let instruction, !instruction.isEmpty else { return fallback }

        let text = instruction.lowercased()

        // U-turns first: the phrase contains a direction word that would otherwise win.
        if text.contains("u-turn") || text.contains("u turn") || text.contains("make a u") {
            return text.contains("right") ? "arrow.uturn.right" : "arrow.uturn.left"
        }

        // Roundabouts before turns, for the same reason — "take the second exit and turn left".
        if text.contains("roundabout") || text.contains("rotary") || text.contains("traffic circle") {
            return "arrow.triangle.turn.up.right.circle"
        }

        if text.contains("destination") || text.contains("arrive") {
            return arrived
        }

        // "Exit" before "right": motorway exits are usually described as an exit, not a turn,
        // and drawing a 90-degree arrow for a slip road is misleading.
        if text.contains("exit") || text.contains("off-ramp") || text.contains("ramp") {
            return text.contains("left") ? "arrow.turn.up.left" : "arrow.turn.up.right"
        }

        // "Keep" and "bear" are gentle; a sharp arrow would overstate them.
        if text.contains("keep") || text.contains("bear") || text.contains("slight") {
            if text.contains("left") { return "arrow.up.left" }
            if text.contains("right") { return "arrow.up.right" }
            return fallback
        }

        if text.contains("merge") {
            return "arrow.merge"
        }

        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }

        return fallback
    }
}
