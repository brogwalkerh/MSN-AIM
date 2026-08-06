import Foundation

/// One tile in the dashboard: a placed instance of a section.
public struct Pane: Hashable, Sendable, Codable, Identifiable {
    public let id: PaneID
    /// What this tile shows. Mutable — "replace what is in this tile" keeps the tile.
    public var sectionID: SectionID
    /// The section's own persisted settings, opaque here. See `SectionState`.
    public var state: SectionState

    public init(id: PaneID = PaneID(), sectionID: SectionID, state: SectionState = .empty) {
        self.id = id
        self.sectionID = sectionID
        self.state = state
    }
}

/// An internal node: two children and the divider between them.
///
/// The divider is not a separate object — the split *is* the divider. That equivalence
/// is the main reason this engine is a tree rather than a grid: dragging a divider
/// mutates exactly one `Double` on exactly one node, with no constraint solving and no
/// way to produce an invalid arrangement.
public struct Split: Hashable, Sendable, Codable {
    public let id: DividerID
    public var axis: SplitAxis
    /// The first child's share of the usable extent, exclusive of the gutter. Always
    /// kept strictly inside (0, 1); the solver clamps it further using minimum sizes.
    public var fraction: Double
    public var first: LayoutNode
    public var second: LayoutNode

    public init(
        id: DividerID = DividerID(),
        axis: SplitAxis,
        fraction: Double = 0.5,
        first: LayoutNode,
        second: LayoutNode
    ) {
        self.id = id
        self.axis = axis
        self.fraction = Self.clampToOpenUnitInterval(fraction)
        self.first = first
        self.second = second
    }

    /// A fraction of exactly 0 or 1 would give a child zero extent, which is a tile the
    /// user can neither see nor drag back. Everything that writes a fraction goes
    /// through here.
    static func clampToOpenUnitInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return Swift.min(Swift.max(value, 0.01), 0.99)
    }
}

/// The layout itself: a binary tree whose leaves are tiles.
///
/// Any tree of this shape tiles its canvas exactly, by construction — there is no
/// arrangement of nodes that leaves a hole or an overlap, so none of the mutations below
/// need to validate that they produced a legal layout. That property is what a
/// grid-with-spans model would have to re-establish on every edit.
public indirect enum LayoutNode: Hashable, Sendable {
    case pane(Pane)
    case split(Split)

    public static func pane(_ sectionID: SectionID) -> LayoutNode {
        .pane(Pane(sectionID: sectionID))
    }

    public static func split(
        _ axis: SplitAxis,
        _ fraction: Double,
        _ first: LayoutNode,
        _ second: LayoutNode
    ) -> LayoutNode {
        .split(Split(axis: axis, fraction: fraction, first: first, second: second))
    }

    public var asPane: Pane? {
        if case .pane(let pane) = self { return pane }
        return nil
    }

    public var asSplit: Split? {
        if case .split(let split) = self { return split }
        return nil
    }
}

// MARK: - Codable

// Written by hand rather than synthesized so the JSON shape is a deliberate, documented
// contract. Saved layouts are migrated across versions (see LayoutMigrator) and asserted
// against a committed golden fixture, both of which are much easier to reason about when
// the encoding is explicit and tagged.
extension LayoutNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, pane, split
    }

    private enum Kind: String, Codable {
        case pane, split
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pane:
            self = .pane(try container.decode(Pane.self, forKey: .pane))
        case .split:
            self = .split(try container.decode(Split.self, forKey: .split))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let pane):
            try container.encode(Kind.pane, forKey: .kind)
            try container.encode(pane, forKey: .pane)
        case .split(let split):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(split, forKey: .split)
        }
    }
}
