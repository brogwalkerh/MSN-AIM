import Foundation
import Testing
@testable import CarDashCore

@Suite("LayoutSolver")
struct LayoutSolverTests {
    private let policy = SectionMetrics.builtInPolicy

    private func canvas(_ size: LayoutSize) -> LayoutRect {
        LayoutRect(origin: .zero, size: size)
    }

    @Test("A single tile fills the canvas")
    func singlePaneFillsCanvas() throws {
        let tree = LayoutTree(.map)
        let solution = LayoutSolver.solve(tree, in: canvas(ReferenceCanvas.phone), policy: policy)

        #expect(solution.dividers.isEmpty)
        let rect = try #require(solution.rect(for: tree.panes[0].id))
        #expect(rect == canvas(ReferenceCanvas.phone))
        LayoutInvariant.tilesExactly(solution)
    }

    @Test("Every preset tiles every reference canvas exactly")
    func presetsTileExactly() {
        for preset in LayoutPresets.all {
            for size in ReferenceCanvas.allLandscape {
                let solution = LayoutSolver.solve(
                    preset.tree(), in: canvas(size), policy: policy
                )
                LayoutInvariant.tilesExactly(solution, "\(preset.id) at \(size.width)×\(size.height)")
                LayoutInvariant.respectsMinimums(
                    solution, policy: policy, "\(preset.id) at \(size.width)×\(size.height)"
                )
            }
        }
    }

    @Test("Random layouts tile exactly", arguments: 0..<200 as Range<UInt64>)
    func randomLayoutsTileExactly(seed: UInt64) {
        let (tree, log) = RandomLayout.tree(seed: seed, operations: 16)
        // A generous canvas: this test is about the solver's arithmetic, not about
        // whether an arbitrary random tree fits a phone.
        let solution = LayoutSolver.solve(
            tree, in: canvas(LayoutSize(width: 4000, height: 3000)), policy: policy
        )
        LayoutInvariant.tilesExactly(solution, "seed \(seed): \(log.joined(separator: "; "))")
    }

    @Test("A canvas with an offset origin is honoured")
    func offsetCanvas() throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: .horizontal, inserting: .music)

        let offset = LayoutRect(x: 44, y: 12, width: 800, height: 380)
        let solution = LayoutSolver.solve(tree, in: offset, policy: policy)

        LayoutInvariant.tilesExactly(solution)
        let first = try #require(solution.rect(for: tree.paneIDs[0]))
        #expect(first.minX == 44)
        #expect(first.minY == 12)
    }

    // MARK: - Clamping

    @Test("A stored fraction that would starve a tile is clamped when drawn")
    func storedFractionClampedNotRewritten() throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: .horizontal, inserting: .music)
        let divider = try #require(tree.splits.first).id
        try tree.setFraction(divider, to: 0.97)

        let solution = LayoutSolver.solve(tree, in: canvas(ReferenceCanvas.phone), policy: policy)
        let solved = try #require(solution.divider(divider))

        #expect(solved.fraction < 0.97, "should have been pulled back to keep music usable")
        LayoutInvariant.respectsMinimums(solution, policy: policy)

        // Crucially the tree itself is untouched. Rotating the phone or opening the app
        // on a smaller screen must not quietly rewrite the layout the user arranged.
        #expect(tree.split(divider)?.fraction == 0.97)
    }

    @Test("The adjustable range reflects both subtrees' minimums")
    func fractionRangeFromMinimums() throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: .horizontal, inserting: .music)

        let size = ReferenceCanvas.phone
        let solution = LayoutSolver.solve(tree, in: canvas(size), policy: policy)
        let divider = try #require(solution.dividers.first)

        let usable = size.width - LayoutMetrics.gutter
        let expectedLower = SectionMetrics.minimumSize(for: .map).width / usable
        let expectedUpper = 1 - SectionMetrics.minimumSize(for: .music).width / usable

        #expect(abs(divider.fractionRange.lowerBound - expectedLower) < 1e-9)
        #expect(abs(divider.fractionRange.upperBound - expectedUpper) < 1e-9)
        #expect(divider.isAdjustable)
    }

    @Test("A divider whose subtrees cannot both fit is frozen rather than inverted")
    func impossibleRangeIsFrozen() throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: .horizontal, inserting: .map, limits: .unlimited)

        // Two maps need 530 points; give them 300.
        let solution = LayoutSolver.solve(
            tree, in: canvas(LayoutSize(width: 300, height: 393)), policy: policy
        )
        let divider = try #require(solution.dividers.first)

        #expect(divider.fractionRange.lowerBound <= divider.fractionRange.upperBound,
                "an inverted range would crash ClosedRange")
        #expect(!divider.isAdjustable)
        // Everything is too small here, but the space is still split sensibly and the
        // layout still tiles.
        LayoutInvariant.tilesExactly(solution)
    }

    // MARK: - Hit targets

    @Test("The divider's touch target is inflated across its axis only",
          arguments: SplitAxis.allCases)
    func hitTargetInflation(axis: SplitAxis) throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: axis, inserting: .music)

        let solution = LayoutSolver.solve(tree, in: canvas(ReferenceCanvas.phone), policy: policy)
        let divider = try #require(solution.dividers.first)
        let slop = LayoutMetrics.dividerHitSlop

        // The bar is only as wide as the gutter; the target around it is finger-sized.
        #expect(axis.extent(of: divider.trackRect.size) == LayoutMetrics.gutter)
        #expect(abs(axis.extent(of: divider.hitRect.size) - (LayoutMetrics.gutter + slop * 2)) < 1e-9)
        #expect(axis.crossExtent(of: divider.hitRect.size) == axis.crossExtent(of: divider.trackRect.size))
        #expect(axis.extent(of: divider.hitRect.size) >= 44, "too small to hit on a bumpy road")
    }
}
