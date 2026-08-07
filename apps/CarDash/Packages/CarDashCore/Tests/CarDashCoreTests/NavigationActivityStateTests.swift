import Foundation
import Testing
@testable import CarDashCore

@Suite("Manoeuvre icons")
struct ManeuverIconTests {
    // MapKit gives instruction text and nothing else — no manoeuvre type, no turn angle. So
    // the arrow is inferred from words, and these are the phrasings that actually come back.
    @Test(
        "Ordinary turns",
        arguments: [
            ("Turn left onto Gower Street", "arrow.turn.up.left"),
            ("Turn right onto High Street", "arrow.turn.up.right"),
            ("TURN LEFT", "arrow.turn.up.left"),
            ("At the end of the road turn right", "arrow.turn.up.right")
        ]
    )
    func turns(instruction: String, expected: String) {
        #expect(ManeuverIcon.symbol(for: instruction) == expected)
    }

    // The whole reason this type is ordered rather than a dictionary: every one of these
    // contains a direction word that a naive match would seize on first.
    @Test(
        "Phrases containing a direction word that is not the manoeuvre",
        arguments: [
            ("Make a U-turn at the roundabout", "arrow.uturn.left"),
            ("Make a U-turn and keep right", "arrow.uturn.right"),
            ("At the roundabout take the second exit and turn left",
             "arrow.triangle.turn.up.right.circle"),
            ("Take the exit on the left", "arrow.turn.up.left"),
            ("Keep left at the fork", "arrow.up.left"),
            ("Bear right onto the slip road", "arrow.up.right"),
            ("Slight left", "arrow.up.left")
        ]
    )
    func ordering(instruction: String, expected: String) {
        #expect(ManeuverIcon.symbol(for: instruction) == expected)
    }

    // A wrong arrow on a lock screen is worse than a neutral one, because a driver may act on
    // it without reading the words underneath.
    @Test(
        "Anything unrecognised gets a neutral arrow rather than a guess",
        arguments: [
            "Continue on Marylebone Road",
            "Proceed to the route",
            "",
            "Follow signs for the city centre"
        ]
    )
    func neutralFallback(instruction: String) {
        #expect(ManeuverIcon.symbol(for: instruction) == ManeuverIcon.fallback)
    }

    @Test("A missing instruction is neutral, not a crash")
    func missingInstruction() {
        #expect(ManeuverIcon.symbol(for: nil) == ManeuverIcon.fallback)
    }

    @Test("Arrival overrides whatever the instruction said")
    func arrivalWins() {
        #expect(ManeuverIcon.symbol(for: "Turn left onto Gower Street", hasArrived: true) == ManeuverIcon.arrived)
        #expect(ManeuverIcon.symbol(for: nil, hasArrived: true) == ManeuverIcon.arrived)
        #expect(ManeuverIcon.symbol(for: "Your destination is on the right") == ManeuverIcon.arrived)
    }

    @Test("Merging is its own thing")
    func merge() {
        #expect(ManeuverIcon.symbol(for: "Merge onto the M4") == "arrow.merge")
    }

    @Test("Every symbol returned is a non-empty name", arguments: [
        "Turn left", "Turn right", "Keep left", "Merge", "Make a U-turn",
        "At the roundabout", "Take the exit", "Continue", ""
    ])
    func alwaysASymbol(instruction: String) {
        #expect(!ManeuverIcon.symbol(for: instruction).isEmpty)
    }
}

@Suite("Live Activity state")
struct NavigationActivityStateTests {
    private let now = Date(timeIntervalSince1970: 1_754_463_600)

    private func guidance(
        instruction: String? = "Turn right onto High Street",
        toManeuver: Double = 400,
        remaining: Double = 12_000,
        eta: TimeInterval = 900,
        arrived: Bool = false
    ) -> GuidanceState {
        GuidanceState(
            currentStepIndex: 0,
            distanceToManeuver: toManeuver,
            distanceRemaining: remaining,
            estimatedTimeRemaining: eta,
            snappedCoordinate: Coordinate(latitude: 51.5, longitude: -0.12),
            crossTrackDistance: 0,
            offRouteConfidence: 0,
            hasArrived: arrived,
            currentInstruction: instruction,
            nextInstruction: nil
        )
    }

    // Everything the widget shows is decided here, because the content state crosses into
    // another process where nothing is testable.
    @Test("Distances arrive already formatted in the user's units")
    func formatting() {
        let metric = NavigationActivityState.from(guidance(), units: .metric, now: now)
        #expect(metric.distanceToManeuver == UnitFormatting.distance(meters: 400, system: .metric))
        #expect(metric.distanceRemaining == UnitFormatting.distance(meters: 12_000, system: .metric))

        let imperial = NavigationActivityState.from(guidance(), units: .imperial, now: now)
        #expect(imperial.distanceToManeuver != metric.distanceToManeuver, "units must actually apply")
    }

    @Test("The arrival date is now plus the time remaining")
    func arrivalDate() {
        let state = NavigationActivityState.from(guidance(eta: 900), units: .metric, now: now)
        #expect(state.arrivalDate == now.addingTimeInterval(900))
        #expect(state.secondsRemaining == 900)
    }

    // A stationary car makes the guidance engine divide by a speed of zero. A countdown that
    // runs backwards, or a widget that refuses to render, is the visible result.
    @Test(
        "Degenerate times remaining are clamped rather than passed through",
        arguments: [-60.0, .infinity, -.infinity, .nan]
    )
    func degenerateETA(eta: TimeInterval) {
        let state = NavigationActivityState.from(guidance(eta: eta), units: .metric, now: now)
        #expect(state.secondsRemaining >= 0)
        #expect(state.secondsRemaining.isFinite)
        #expect(state.arrivalDate >= now)
    }

    @Test("Arrival replaces the instruction as well as the icon")
    func arrival() {
        let state = NavigationActivityState.from(
            guidance(instruction: "Turn left onto Gower Street", arrived: true),
            units: .metric,
            now: now
        )
        #expect(state.hasArrived)
        #expect(state.instruction == "You have arrived")
        #expect(state.maneuverSymbol == ManeuverIcon.arrived)
    }

    @Test("A route with no instruction still says something")
    func noInstruction() {
        let state = NavigationActivityState.from(guidance(instruction: nil), units: .metric, now: now)
        #expect(state.instruction == "Continue")
        #expect(!state.instruction.isEmpty)
    }

    // The state is encoded and decoded by ActivityKit on every update, across a process
    // boundary. Anything that fails to round trip simply stops the lock screen updating.
    @Test("Round trips through JSON, which is how ActivityKit moves it")
    func codable() throws {
        let state = NavigationActivityState.from(guidance(), units: .metric, now: now)
        let decoded = try JSONDecoder().decode(
            NavigationActivityState.self,
            from: try JSONEncoder().encode(state)
        )
        #expect(decoded == state)
    }
}
