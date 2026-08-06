import Foundation

/// A complete arrangement of tiles.
///
/// Pure structural algebra: no geometry (that is `LayoutSolver`), no persistence (that
/// is `LayoutCodec`), no knowledge of what a section renders. Every mutation preserves
/// the invariant that the tree tiles its canvas exactly, because there is no way to
/// express a tree that does not.
public struct LayoutTree: Hashable, Sendable, Codable {
    public var root: LayoutNode

    public init(root: LayoutNode) {
        self.root = root
    }

    /// A layout with a single tile filling the canvas.
    public init(_ sectionID: SectionID) {
        self.init(root: .pane(sectionID))
    }

    // MARK: - Queries

    /// Tiles in depth-first order — the order they appear reading left-to-right,
    /// top-to-bottom, which is also the order the overflow rail uses.
    public var panes: [Pane] {
        Self.panes(in: root)
    }

    public var paneIDs: [PaneID] {
        panes.map(\.id)
    }

    public var paneCount: Int {
        Self.paneCount(in: root)
    }

    /// Number of levels. A single tile is 1; a tile split in two is 2.
    public var depth: Int {
        Self.depth(of: root)
    }

    public var splits: [Split] {
        Self.splits(in: root)
    }

    public func pane(_ id: PaneID) -> Pane? {
        panes.first { $0.id == id }
    }

    public func contains(_ id: PaneID) -> Bool {
        pane(id) != nil
    }

    public func split(_ id: DividerID) -> Split? {
        splits.first { $0.id == id }
    }

    /// The sections in use, deduplicated, in first-appearance order.
    public var sectionIDs: [SectionID] {
        var seen = Set<SectionID>()
        return panes.compactMap { seen.insert($0.sectionID).inserted ? $0.sectionID : nil }
    }

    /// The smallest canvas this layout can be drawn in without violating any section's
    /// minimum size.
    ///
    /// A bottom-up fold: along a split's axis the children's minimums add (plus the
    /// gutter between them); across it they take the maximum. This one function backs
    /// resize clamping, "can this tile be split?", and the portrait adaptation.
    public func minimumSize(
        policy: MinimumSizePolicy = .uniform,
        gutter: Double = LayoutMetrics.gutter
    ) -> LayoutSize {
        Self.minimumSize(of: root, policy: policy, gutter: gutter)
    }

    // MARK: - Mutations

    /// Divides `paneID`'s tile in two, putting `sectionID` in the new half.
    ///
    /// - Returns: the id of the newly created tile.
    @discardableResult
    public mutating func split(
        _ paneID: PaneID,
        axis: SplitAxis,
        inserting sectionID: SectionID,
        placingNewPaneFirst: Bool = false,
        fraction: Double = 0.5,
        fitting canvas: LayoutSize? = nil,
        policy: MinimumSizePolicy = .uniform,
        gutter: Double = LayoutMetrics.gutter,
        limits: SplitLimits = .phone
    ) throws -> PaneID {
        guard contains(paneID) else { throw LayoutError.paneNotFound(paneID) }
        guard paneCount < limits.maxPanes else {
            throw LayoutError.maximumPanesExceeded(limit: limits.maxPanes)
        }

        let newPane = Pane(sectionID: sectionID)
        var candidate = self
        candidate.root = Self.replacingPane(in: root, id: paneID) { existing in
            let existingNode = LayoutNode.pane(existing)
            let newNode = LayoutNode.pane(newPane)
            return .split(Split(
                axis: axis,
                fraction: fraction,
                first: placingNewPaneFirst ? newNode : existingNode,
                second: placingNewPaneFirst ? existingNode : newNode
            ))
        } ?? root

        guard candidate.depth <= limits.maxDepth else {
            throw LayoutError.maximumDepthExceeded(limit: limits.maxDepth)
        }

        // Checked against the real canvas rather than assumed: a split that leaves the
        // map 40 points wide is not a smaller map, it is an unusable one, and it is
        // better to refuse than to render it.
        if let canvas {
            let needed = candidate.minimumSize(policy: policy, gutter: gutter)
            guard canvas.canContain(needed) else {
                throw LayoutError.wouldNotFit(needed: needed, available: canvas)
            }
        }

        self = candidate
        return newPane.id
    }

    /// Removes a tile, giving its space to its sibling.
    ///
    /// The parent split collapses into the surviving subtree, so the result still tiles
    /// the canvas exactly with no gap to fill and no heuristic to pick.
    public mutating func remove(_ paneID: PaneID) throws {
        guard contains(paneID) else { throw LayoutError.paneNotFound(paneID) }
        guard paneCount > 1 else { throw LayoutError.cannotRemoveLastPane }

        switch Self.removing(paneID, from: root) {
        case .notFound:
            throw LayoutError.paneNotFound(paneID)
        case .emptied:
            // Unreachable: paneCount > 1 means the root is a split, and a split can only
            // report .emptied if both children vanished, which cannot happen.
            throw LayoutError.cannotRemoveLastPane
        case .replaced(let node):
            root = node
        }
    }

    /// Changes what a tile shows, keeping the tile itself.
    ///
    /// The old section's state is discarded, because it belongs to that section's
    /// schema, not to the tile.
    public mutating func replace(_ paneID: PaneID, with sectionID: SectionID) throws {
        guard contains(paneID) else { throw LayoutError.paneNotFound(paneID) }
        root = Self.replacingPane(in: root, id: paneID) { pane in
            .pane(Pane(id: pane.id, sectionID: sectionID, state: .empty))
        } ?? root
    }

    /// Swaps two tiles' positions.
    ///
    /// The whole `Pane` moves, identity included, so SwiftUI sees two tiles trading
    /// places and can animate it — rather than two stationary tiles whose contents
    /// abruptly change.
    public mutating func exchange(_ a: PaneID, _ b: PaneID) throws {
        guard let paneA = pane(a) else { throw LayoutError.paneNotFound(a) }
        guard let paneB = pane(b) else { throw LayoutError.paneNotFound(b) }
        guard a != b else { return }

        var node = Self.replacingPane(in: root, id: a) { _ in .pane(paneB) } ?? root
        node = Self.replacingPane(in: node, id: b) { _ in .pane(paneA) } ?? node
        root = node
    }

    public mutating func setFraction(_ dividerID: DividerID, to fraction: Double) throws {
        guard split(dividerID) != nil else { throw LayoutError.dividerNotFound(dividerID) }
        root = Self.replacingSplit(in: root, id: dividerID) { existing in
            var updated = existing
            updated.fraction = Split.clampToOpenUnitInterval(fraction)
            return updated
        } ?? root
    }

    public mutating func setState(_ state: SectionState, for paneID: PaneID) throws {
        guard contains(paneID) else { throw LayoutError.paneNotFound(paneID) }
        root = Self.replacingPane(in: root, id: paneID) { pane in
            .pane(Pane(id: pane.id, sectionID: pane.sectionID, state: state))
        } ?? root
    }

    // MARK: - Recursion

    private static func panes(in node: LayoutNode) -> [Pane] {
        switch node {
        case .pane(let pane):
            return [pane]
        case .split(let split):
            return panes(in: split.first) + panes(in: split.second)
        }
    }

    private static func paneCount(in node: LayoutNode) -> Int {
        switch node {
        case .pane:
            return 1
        case .split(let split):
            return paneCount(in: split.first) + paneCount(in: split.second)
        }
    }

    private static func splits(in node: LayoutNode) -> [Split] {
        guard case .split(let split) = node else { return [] }
        return [split] + splits(in: split.first) + splits(in: split.second)
    }

    private static func depth(of node: LayoutNode) -> Int {
        switch node {
        case .pane:
            return 1
        case .split(let split):
            return 1 + Swift.max(depth(of: split.first), depth(of: split.second))
        }
    }

    static func minimumSize(
        of node: LayoutNode,
        policy: MinimumSizePolicy,
        gutter: Double
    ) -> LayoutSize {
        switch node {
        case .pane(let pane):
            return policy(pane.sectionID)
        case .split(let split):
            let first = minimumSize(of: split.first, policy: policy, gutter: gutter)
            let second = minimumSize(of: split.second, policy: policy, gutter: gutter)
            let along = split.axis.extent(of: first) + gutter + split.axis.extent(of: second)
            let across = Swift.max(
                split.axis.crossExtent(of: first),
                split.axis.crossExtent(of: second)
            )
            return split.axis.size(extent: along, crossExtent: across)
        }
    }

    /// Rebuilds the tree with one leaf transformed. Returns nil if the leaf is absent,
    /// so callers can distinguish "not found" from "found and unchanged".
    private static func replacingPane(
        in node: LayoutNode,
        id: PaneID,
        transform: (Pane) -> LayoutNode
    ) -> LayoutNode? {
        switch node {
        case .pane(let pane):
            return pane.id == id ? transform(pane) : nil
        case .split(let split):
            if let updated = replacingPane(in: split.first, id: id, transform: transform) {
                var copy = split
                copy.first = updated
                return .split(copy)
            }
            if let updated = replacingPane(in: split.second, id: id, transform: transform) {
                var copy = split
                copy.second = updated
                return .split(copy)
            }
            return nil
        }
    }

    private static func replacingSplit(
        in node: LayoutNode,
        id: DividerID,
        transform: (Split) -> Split
    ) -> LayoutNode? {
        guard case .split(let split) = node else { return nil }
        if split.id == id {
            return .split(transform(split))
        }
        if let updated = replacingSplit(in: split.first, id: id, transform: transform) {
            var copy = split
            copy.first = updated
            return .split(copy)
        }
        if let updated = replacingSplit(in: split.second, id: id, transform: transform) {
            var copy = split
            copy.second = updated
            return .split(copy)
        }
        return nil
    }

    private enum Removal {
        case notFound
        /// The subtree consisted only of the removed pane — the caller should promote
        /// the sibling in its place.
        case emptied
        case replaced(LayoutNode)
    }

    private static func removing(_ id: PaneID, from node: LayoutNode) -> Removal {
        switch node {
        case .pane(let pane):
            return pane.id == id ? .emptied : .notFound

        case .split(let split):
            switch removing(id, from: split.first) {
            case .emptied:
                return .replaced(split.second)
            case .replaced(let updated):
                var copy = split
                copy.first = updated
                return .replaced(.split(copy))
            case .notFound:
                break
            }

            switch removing(id, from: split.second) {
            case .emptied:
                return .replaced(split.first)
            case .replaced(let updated):
                var copy = split
                copy.second = updated
                return .replaced(.split(copy))
            case .notFound:
                return .notFound
            }
        }
    }
}
