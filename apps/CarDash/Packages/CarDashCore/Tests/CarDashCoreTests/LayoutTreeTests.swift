import Foundation
import Testing
@testable import CarDashCore

@Suite("LayoutTree")
struct LayoutTreeTests {
    private let policy = SectionMetrics.builtInPolicy

    // MARK: - Structure

    @Test("A new tree is a single tile filling the canvas")
    func singlePane() {
        let tree = LayoutTree(.map)
        #expect(tree.paneCount == 1)
        #expect(tree.depth == 1)
        #expect(tree.splits.isEmpty)
        #expect(tree.sectionIDs == [.map])
    }

    @Test("Splitting adds one tile and one divider", arguments: SplitAxis.allCases)
    func splitAddsPaneAndDivider(axis: SplitAxis) throws {
        var tree = LayoutTree(.map)
        let original = try #require(tree.panes.first).id

        let added = try tree.split(original, axis: axis, inserting: .music)

        #expect(tree.paneCount == 2)
        #expect(tree.depth == 2)
        #expect(tree.splits.count == 1)
        #expect(tree.splits[0].axis == axis)
        #expect(tree.paneIDs == [original, added])
        #expect(tree.pane(added)?.sectionID == .music)
    }

    @Test("placingNewPaneFirst puts the new tile before the existing one")
    func splitOrdering() throws {
        var tree = LayoutTree(.map)
        let original = try #require(tree.panes.first).id
        let added = try tree.split(original, axis: .horizontal, inserting: .music, placingNewPaneFirst: true)
        #expect(tree.paneIDs == [added, original])
    }

    // This is the pair of operations most likely to drift apart, and the cheapest
    // possible statement of "the tree algebra is sound": undoing a split must leave
    // exactly what was there before, identity included.
    @Test("Removing a freshly split tile restores the original tree", arguments: 0..<64 as Range<UInt64>)
    func splitThenRemoveIsIdentity(seed: UInt64) throws {
        let (original, log) = RandomLayout.tree(seed: seed)
        var tree = original

        let target = try #require(tree.panes.randomElement())
        let added = try tree.split(
            target.id,
            axis: .horizontal,
            inserting: .clock,
            limits: .unlimited
        )
        try tree.remove(added)

        #expect(tree == original, "seed \(seed): \(log.joined(separator: "; "))")
    }

    @Test("Removing a tile gives its space to its sibling")
    func removeCollapsesParent() throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        let music = try tree.split(map, axis: .horizontal, inserting: .music)
        let gauges = try tree.split(music, axis: .vertical, inserting: .gauges)

        try tree.remove(gauges)

        #expect(tree.paneCount == 2)
        #expect(tree.sectionIDs == [.map, .music])
        // The nested split collapsed entirely rather than leaving an empty node behind.
        #expect(tree.depth == 2)
        #expect(tree.splits.count == 1)
    }

    @Test("The last remaining tile cannot be removed")
    func cannotRemoveLastPane() throws {
        var tree = LayoutTree(.map)
        let only = try #require(tree.panes.first).id
        #expect(throws: LayoutError.cannotRemoveLastPane) {
            try tree.remove(only)
        }
        #expect(tree.paneCount == 1)
    }

    @Test("Operations on unknown identifiers throw rather than silently doing nothing")
    func unknownIdentifiers() throws {
        var tree = LayoutTree(.map)
        let ghost = PaneID()
        let noDivider = DividerID()

        #expect(throws: LayoutError.paneNotFound(ghost)) { try tree.remove(ghost) }
        #expect(throws: LayoutError.paneNotFound(ghost)) { try tree.replace(ghost, with: .music) }
        #expect(throws: LayoutError.dividerNotFound(noDivider)) { try tree.setFraction(noDivider, to: 0.5) }
        #expect(throws: LayoutError.paneNotFound(ghost)) {
            try tree.split(ghost, axis: .horizontal, inserting: .music)
        }
    }

    @Test("Replacing a tile keeps the tile and drops the old section's state")
    func replaceKeepsIdentity() throws {
        var tree = LayoutTree(.map)
        let id = try #require(tree.panes.first).id
        try tree.setState(SectionState(data: Data([1, 2, 3])), for: id)

        try tree.replace(id, with: .weather)

        let pane = try #require(tree.pane(id))
        #expect(pane.id == id, "the tile itself should survive a content change")
        #expect(pane.sectionID == .weather)
        #expect(pane.state.isEmpty, "state belongs to the old section's schema, not the tile")
    }

    @Test("Exchanging two tiles moves their identities with their content")
    func exchangeMovesIdentity() throws {
        var tree = LayoutTree(.map)
        let a = try #require(tree.panes.first).id
        let b = try tree.split(a, axis: .horizontal, inserting: .music)

        try tree.exchange(a, b)

        // The ids travel with the content, so SwiftUI sees two tiles swapping places and
        // can animate it, rather than two fixed tiles whose contents jump.
        #expect(tree.paneIDs == [b, a])
        #expect(tree.pane(a)?.sectionID == .map)
        #expect(tree.pane(b)?.sectionID == .music)
    }

    @Test("Exchanging a tile with itself is a no-op")
    func exchangeWithSelf() throws {
        var tree = LayoutTree(.map)
        let id = try #require(tree.panes.first).id
        let before = tree
        try tree.exchange(id, id)
        #expect(tree == before)
    }

    // MARK: - Limits

    @Test("Splitting past the tile limit is refused")
    func maxPanesEnforced() throws {
        var tree = LayoutTree(.map)
        let limits = SplitLimits(maxPanes: 3, maxDepth: 10)

        var current = try #require(tree.panes.first).id
        current = try tree.split(current, axis: .horizontal, inserting: .music, limits: limits)
        current = try tree.split(current, axis: .horizontal, inserting: .gauges, limits: limits)

        #expect(throws: LayoutError.maximumPanesExceeded(limit: 3)) {
            try tree.split(current, axis: .horizontal, inserting: .clock, limits: limits)
        }
        #expect(tree.paneCount == 3)
    }

    @Test("Splitting past the nesting limit is refused")
    func maxDepthEnforced() throws {
        var tree = LayoutTree(.map)
        let limits = SplitLimits(maxPanes: 99, maxDepth: 3)

        var current = try #require(tree.panes.first).id
        current = try tree.split(current, axis: .horizontal, inserting: .music, limits: limits)
        current = try tree.split(current, axis: .vertical, inserting: .gauges, limits: limits)
        #expect(tree.depth == 3)

        #expect(throws: LayoutError.maximumDepthExceeded(limit: 3)) {
            try tree.split(current, axis: .horizontal, inserting: .clock, limits: limits)
        }
    }

    @Test("A split that would starve a tile is refused, and changes nothing")
    func splitRefusedWhenItWouldNotFit() throws {
        var tree = LayoutTree(.map)
        let id = try #require(tree.panes.first).id
        let before = tree
        // Two maps side by side need 260 + 10 + 260 = 530 points of width.
        let canvas = LayoutSize(width: 400, height: 393)

        #expect(throws: (any Error).self) {
            try tree.split(id, axis: .horizontal, inserting: .map, fitting: canvas, policy: policy)
        }
        #expect(tree == before, "a refused split must not leave the tree half-modified")

        // The same split on a real phone canvas is fine.
        #expect(throws: Never.self) {
            try tree.split(
                id, axis: .horizontal, inserting: .map,
                fitting: ReferenceCanvas.phone, policy: policy
            )
        }
    }

    // MARK: - Fractions

    @Test("Fractions are held strictly inside 0 and 1")
    func fractionsClamped() throws {
        var tree = LayoutTree(.map)
        let id = try #require(tree.panes.first).id
        try tree.split(id, axis: .horizontal, inserting: .music)
        let divider = try #require(tree.splits.first).id

        for value in [-5.0, 0.0, 1.0, 42.0, .infinity, .nan] as [Double] {
            try tree.setFraction(divider, to: value)
            let fraction = try #require(tree.split(divider)).fraction
            #expect(fraction > 0 && fraction < 1, "fraction \(value) produced \(fraction)")
        }
    }

    // MARK: - Minimum sizes

    @Test("Minimum size adds along the split axis and takes the max across it")
    func minimumSizeFold() throws {
        var tree = LayoutTree(.map)
        let map = try #require(tree.panes.first).id
        try tree.split(map, axis: .horizontal, inserting: .clock)

        let mapMin = SectionMetrics.minimumSize(for: .map)
        let clockMin = SectionMetrics.minimumSize(for: .clock)
        let gutter = LayoutMetrics.gutter

        let minimum = tree.minimumSize(policy: policy, gutter: gutter)
        #expect(minimum.width == mapMin.width + gutter + clockMin.width)
        #expect(minimum.height == max(mapMin.height, clockMin.height))
    }

    @Test("A nested tile's minimum propagates all the way to the root")
    func minimumSizePropagatesThroughNesting() throws {
        var tree = LayoutTree(.clock)
        let clock = try #require(tree.panes.first).id
        let second = try tree.split(clock, axis: .horizontal, inserting: .clock, limits: .unlimited)
        try tree.split(second, axis: .horizontal, inserting: .map, limits: .unlimited)

        let clockMin = SectionMetrics.minimumSize(for: .clock)
        let mapMin = SectionMetrics.minimumSize(for: .map)
        let gutter = LayoutMetrics.gutter

        // clock | (clock | map) — three tiles and two gutters across.
        let expected = clockMin.width * 2 + mapMin.width + gutter * 2
        #expect(tree.minimumSize(policy: policy, gutter: gutter).width == expected)
    }

    // MARK: - Property tests

    @Test("Random editing sequences always produce a well-formed tree",
          arguments: 0..<200 as Range<UInt64>)
    func randomSequencesStayValid(seed: UInt64) throws {
        let (tree, log) = RandomLayout.tree(seed: seed, operations: 16)
        let context = "seed \(seed): \(log.joined(separator: "; "))"

        #expect(tree.paneCount >= 1, "\(context)")
        #expect(tree.paneCount == tree.panes.count, "\(context)")
        #expect(Set(tree.paneIDs).count == tree.paneIDs.count, "duplicate pane ids. \(context)")
        #expect(Set(tree.splits.map(\.id)).count == tree.splits.count, "duplicate divider ids. \(context)")
        // A binary tree with n leaves has exactly n-1 internal nodes. If this ever fails,
        // a mutation has left a split with a missing or duplicated child.
        #expect(tree.splits.count == tree.paneCount - 1, "\(context)")
        for split in tree.splits {
            #expect(split.fraction > 0 && split.fraction < 1, "\(context)")
        }
    }
}
