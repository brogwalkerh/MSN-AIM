import Foundation
import Testing
@testable import CarDashCore

@Suite("GuidanceEngine")
struct GuidanceEngineTests {
    private let route = TestRoute.lShaped()

    private func run(_ fixes: [GeoFix], engine: inout GuidanceEngine) -> [ManeuverPrompt] {
        var prompts: [ManeuverPrompt] = []
        for fix in fixes {
            prompts.append(contentsOf: engine.update(with: fix))
        }
        return prompts
    }

    // MARK: - Following a route

    @Test("Driving the route advances through its steps in order")
    func followsTheRoute() {
        var engine = GuidanceEngine(route: route)
        var stepIndices: [Int] = []
        var remaining: [Double] = []

        for fix in TestRoute.drive(route) {
            engine.update(with: fix)
            guard let state = engine.state else { continue }
            stepIndices.append(state.currentStepIndex)
            remaining.append(state.distanceRemaining)
        }

        #expect(stepIndices.first == 0)
        #expect(stepIndices.contains(1), "never reached the second step")
        #expect(stepIndices == stepIndices.sorted(), "steps went backwards")
        #expect(engine.state?.hasArrived == true)
    }

    @Test("Distance remaining only ever decreases")
    func distanceIsMonotonic() {
        var engine = GuidanceEngine(route: route)
        var previous = Double.infinity

        for fix in TestRoute.drive(route) {
            engine.update(with: fix)
            guard let remaining = engine.state?.distanceRemaining else { continue }
            #expect(remaining <= previous + 1, "went from \(previous) to \(remaining)")
            previous = remaining
        }
        #expect(previous < 30, "should have finished at the destination, ended \(previous) m away")
    }

    @Test("The snapped position stays on the route")
    func snappingStaysOnRoute() {
        var engine = GuidanceEngine(route: route)
        for fix in TestRoute.drive(route) {
            engine.update(with: fix)
            guard let state = engine.state else { continue }
            #expect(state.crossTrackDistance < 5)
            #expect(GeoMath.distance(from: state.snappedCoordinate, to: fix.coordinate) < 5)
        }
    }

    @Test("Distance to the manoeuvre counts down to the turn")
    func distanceToManeuver() {
        var engine = GuidanceEngine(route: route)
        var lastOnFirstStep: Double?

        for fix in TestRoute.drive(route) {
            engine.update(with: fix)
            guard let state = engine.state else { continue }
            if state.currentStepIndex == 0 { lastOnFirstStep = state.distanceToManeuver }
        }
        // The final reading before the turn should be close to it.
        #expect((lastOnFirstStep ?? .infinity) < 60)
    }

    // MARK: - Prompts

    @Test("Each prompt fires exactly once")
    func promptsFireOnce() {
        var engine = GuidanceEngine(route: route)
        let prompts = run(TestRoute.drive(route), engine: &engine)
        let ids = prompts.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate prompts: \(ids)")
    }

    @Test("Prompts arrive in descending distance order within a step")
    func promptOrdering() {
        var engine = GuidanceEngine(route: route)
        let prompts = run(TestRoute.drive(route), engine: &engine)

        let firstStep = prompts.filter { $0.stepIndex == 0 }.map(\.trigger)
        #expect(firstStep == [.twoKilometres, .fiveHundredMetres, .oneHundredMetres, .now])
    }

    // Entering a 1 km step immediately satisfies "distance to manoeuvre is under 2 km".
    // Announcing "In 2 kilometres, turn right" at that moment is both wrong and the kind
    // of thing that makes a driver stop trusting the voice.
    @Test("A step shorter than a trigger's distance does not announce it")
    func shortStepSuppressesDistantPrompt() {
        var engine = GuidanceEngine(route: route)
        let prompts = run(TestRoute.drive(route), engine: &engine)

        let secondStep = prompts.filter { $0.stepIndex == 1 }.map(\.trigger)
        #expect(!secondStep.contains(.twoKilometres), "the second step is only 1 km long")
        #expect(secondStep.contains(.fiveHundredMetres))
        #expect(secondStep.contains(.now))
    }

    @Test("Prompt text is ready to speak")
    func promptText() {
        var engine = GuidanceEngine(route: route)
        let prompts = run(TestRoute.drive(route), engine: &engine)

        let twoKm = prompts.first { $0.trigger == .twoKilometres }
        #expect(twoKm?.text == "In 2 kilometres, Head north on Long Road")

        let now = prompts.first { $0.stepIndex == 1 && $0.trigger == .now }
        #expect(now?.text == "Turn right onto East Street")
    }

    @Test("Arrival is announced exactly once")
    func arrival() {
        var engine = GuidanceEngine(route: route)
        let prompts = run(TestRoute.drive(route), engine: &engine)
        let arrivals = prompts.filter { $0.trigger == .arrival }

        #expect(arrivals.count == 1)
        #expect(arrivals.first?.text == "You have arrived.")
    }

    // MARK: - Going wrong

    // The single most important thing this engine must not do. Recalculating on one bad
    // fix means the route flips every time the car passes a tall building.
    @Test("One wild fix does not put the car off route")
    func singleGlitchIsIgnored() {
        var engine = GuidanceEngine(route: route)
        let fixes = TestRoute.withGlitch(TestRoute.drive(route), at: 20)

        var everWentOffRoute = false
        for fix in fixes {
            engine.update(with: fix)
            if engine.state?.isOffRoute == true { everWentOffRoute = true }
        }
        #expect(!everWentOffRoute, "a 500 m outlier triggered a reroute")
    }

    @Test("A sustained departure is detected")
    func wrongTurnIsDetected() {
        var engine = GuidanceEngine(route: route)
        let fixes = TestRoute.withWrongTurn(TestRoute.drive(route), from: 20)

        var offRouteAt: Int?
        for (index, fix) in fixes.enumerated() {
            engine.update(with: fix)
            if engine.state?.isOffRoute == true, offRouteAt == nil { offRouteAt = index }
        }

        #expect(offRouteAt != nil, "never noticed the car had left the route")
        if let detected = offRouteAt {
            #expect(detected >= 20, "flagged before the departure began")
            #expect(detected <= 30, "took \(detected - 20) fixes to notice")
        }
    }

    @Test("Confidence builds before it is acted on")
    func confidenceIsGradual() {
        var engine = GuidanceEngine(route: route)
        let fixes = TestRoute.withWrongTurn(TestRoute.drive(route), from: 20)
        var sawPartialConfidence = false

        for fix in fixes {
            engine.update(with: fix)
            if let confidence = engine.state?.offRouteConfidence, confidence > 0, confidence < 1 {
                sawPartialConfidence = true
            }
        }
        #expect(sawPartialConfidence, "went from certain to certain with no doubt in between")
    }

    // Instructions relate to a road the car is no longer on, so silence beats confidence.
    @Test("Prompts stop while off route")
    func offRouteSilencesPrompts() {
        var engine = GuidanceEngine(route: route)
        let fixes = TestRoute.withWrongTurn(TestRoute.drive(route), from: 5)

        var promptsWhileOffRoute = 0
        for fix in fixes {
            let prompts = engine.update(with: fix)
            if engine.state?.isOffRoute == true {
                promptsWhileOffRoute += prompts.count
            }
        }
        #expect(promptsWhileOffRoute == 0)
    }

    // MARK: - Bad input

    @Test("Fixes too inaccurate to mean anything are ignored")
    func poorAccuracyIgnored() {
        var engine = GuidanceEngine(route: route)
        let clean = TestRoute.drive(route)

        for fix in clean.prefix(10) { engine.update(with: fix) }
        let before = engine.state

        let useless = GeoFix(
            coordinate: TestRoute.offset(TestRoute.origin, east: 3000),
            speed: 13,
            horizontalAccuracy: 900,
            timestamp: clean[10].timestamp
        )
        engine.update(with: useless)

        #expect(engine.state == before, "a 900 m accuracy fix moved the state")
    }

    @Test("An empty route produces no state and does not crash")
    func emptyRoute() {
        var engine = GuidanceEngine(
            route: Route(name: "Empty", steps: [], totalDistance: 0, expectedTravelTime: 0)
        )
        let prompts = engine.update(with: GeoFix(coordinate: TestRoute.origin, timestamp: Date()))
        #expect(prompts.isEmpty)
        #expect(engine.state == nil)
    }

    @Test("Reset allows the same engine to be reused")
    func reset() {
        var engine = GuidanceEngine(route: route)
        let fixes = TestRoute.drive(route)
        _ = run(fixes, engine: &engine)

        engine.reset()
        #expect(engine.state == nil)

        let second = run(fixes, engine: &engine)
        #expect(!second.isEmpty, "prompts should fire again after a reset")
        #expect(second.contains { $0.trigger == .arrival })
    }

    @Test("ETA uses the current speed when there is one")
    func etaFromSpeed() {
        var engine = GuidanceEngine(route: route)
        let fixes = TestRoute.drive(route, speed: 20)
        for fix in fixes.prefix(5) { engine.update(with: fix) }

        let state = engine.state
        #expect(state != nil)
        if let state {
            let expected = state.distanceRemaining / 20
            #expect(abs(state.estimatedTimeRemaining - expected) < 1)
        }
    }
}
