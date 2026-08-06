import Foundation
import Testing
@testable import CarDashCore

@Suite("DividerDrag")
struct DividerDragTests {
    private func drag(
        start: Double = 0.5,
        usable: Double = 800,
        range: ClosedRange<Double> = 0.2...0.8,
        axis: SplitAxis = .horizontal
    ) -> DividerDrag {
        DividerDrag(
            dividerID: DividerID(),
            axis: axis,
            startFraction: start,
            usableExtent: usable,
            range: range
        )
    }

    @Test("Translation converts to fraction against the usable extent")
    func basicArithmetic() {
        let subject = drag(start: 0.5, usable: 800)
        #expect(subject.fraction(forTranslation: 0) == 0.5)
        #expect(abs(subject.fraction(forTranslation: 80) - 0.6) < 1e-12)
        #expect(abs(subject.fraction(forTranslation: -80) - 0.4) < 1e-12)
    }

    // The reason this type exists. Written incrementally — fraction += delta/extent on
    // each gesture update — a drag that runs past the clamp keeps accumulating against a
    // value that no longer tracks the finger, so dragging back leaves the divider
    // somewhere it was never dropped. Absolute arithmetic makes over-dragging free.
    @Test("Over-dragging and returning lands exactly where it started")
    func clampIsIdempotent() {
        let subject = drag(start: 0.5, usable: 800, range: 0.2...0.8)

        #expect(subject.fraction(forTranslation: 100_000) == 0.8)
        #expect(subject.fraction(forTranslation: -100_000) == 0.2)
        // Straight back to the origin of the gesture.
        #expect(subject.fraction(forTranslation: 0) == 0.5)
        // And a partial return is proportional, not offset by how far it overshot.
        #expect(abs(subject.fraction(forTranslation: 80) - 0.6) < 1e-12)
    }

    @Test("A sequence of translations depends only on the latest value")
    func pathIndependence() {
        let subject = drag(start: 0.5, usable: 800, range: 0.2...0.8)
        let wandering = [0, 500, -900, 12_000, -40, 160.0]
        for value in wandering {
            _ = subject.fraction(forTranslation: value)
        }
        #expect(subject.fraction(forTranslation: 160) == subject.fraction(forTranslation: 160))
        #expect(abs(subject.fraction(forTranslation: 160) - 0.7) < 1e-12)
    }

    @Test("Clamping is reported so the view can stop following and buzz")
    func clampDetection() {
        let subject = drag(start: 0.5, usable: 800, range: 0.2...0.8)
        #expect(!subject.isClamped(atTranslation: 100))
        #expect(subject.isClamped(atTranslation: 400))
        #expect(subject.isClamped(atTranslation: -400))
    }

    @Test("A degenerate parent cannot be dragged")
    func zeroExtentIsInert() {
        let subject = drag(start: 0.42, usable: 0)
        #expect(subject.fraction(forTranslation: 250) == 0.42)
        #expect(subject.isClamped(atTranslation: 250))
    }

    @Test("A frozen divider stays put")
    func frozenRange() {
        let subject = drag(start: 0.5, usable: 800, range: 0.5...0.5)
        #expect(subject.fraction(forTranslation: 300) == 0.5)
        #expect(subject.fraction(forTranslation: -300) == 0.5)
    }

    // Real gestures never produce these. Holding the divider still is the safe
    // response — a NaN fraction would propagate into the solver and produce NaN rects,
    // which SwiftUI renders as nothing at all.
    @Test("Non-finite translation holds position rather than propagating")
    func nonFiniteTranslation() {
        let subject = drag(start: 0.5, usable: 800)
        #expect(subject.fraction(forTranslation: .nan) == 0.5)
        #expect(subject.fraction(forTranslation: .infinity) == 0.5)
        #expect(subject.fraction(forTranslation: -.infinity) == 0.5)
    }

    @Test("A drag follows x for a side-by-side split and y for a stacked one")
    func axisProjection() {
        #expect(drag(axis: .horizontal).translation(fromDX: 30, dy: -90) == 30)
        #expect(drag(axis: .vertical).translation(fromDX: 30, dy: -90) == -90)
    }

    // MARK: - Against the solver

    @Test("A drag built from a solved divider inherits the right extent and range",
          arguments: SplitAxis.allCases)
    func builtFromSolvedDivider(axis: SplitAxis) throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: axis, inserting: .music)

        let canvas = LayoutRect(origin: .zero, size: ReferenceCanvas.phone)
        let solution = LayoutSolver.solve(tree, in: canvas, policy: SectionMetrics.builtInPolicy)
        let solved = try #require(solution.dividers.first)
        let subject = DividerDrag(divider: solved)

        #expect(subject.startFraction == solved.fraction)
        #expect(subject.range == solved.fractionRange)
        #expect(abs(subject.usableExtent - (axis.extent(of: canvas.size) - LayoutMetrics.gutter)) < 1e-9)
    }

    // Ties the drag arithmetic back to the thing it exists to protect: whatever the
    // finger does, the tiles it produces are still legal.
    @Test("Dragging to any position leaves every tile at or above its minimum",
          arguments: [-2000.0, -300, -1, 0, 1, 300, 2000])
    func draggingNeverStarvesATile(translation: Double) throws {
        let policy = SectionMetrics.builtInPolicy
        var tree = LayoutPresets.navigationFocus
        let canvas = LayoutRect(origin: .zero, size: ReferenceCanvas.phone)

        let solution = LayoutSolver.solve(tree, in: canvas, policy: policy)
        let solved = try #require(solution.dividers.first)
        let subject = DividerDrag(divider: solved)

        try tree.setFraction(solved.id, to: subject.fraction(forTranslation: translation))

        let after = LayoutSolver.solve(tree, in: canvas, policy: policy)
        LayoutInvariant.respectsMinimums(after, policy: policy, "after dragging \(translation)")
        LayoutInvariant.tilesExactly(after, "after dragging \(translation)")
    }
}
