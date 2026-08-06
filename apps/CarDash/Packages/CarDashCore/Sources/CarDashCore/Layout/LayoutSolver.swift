import Foundation

/// A divider with everything the view layer needs to draw and drag it.
public struct SolvedDivider: Hashable, Sendable, Identifiable {
    public let id: DividerID
    public let axis: SplitAxis
    /// The visible bar, exactly the gutter's width.
    public let trackRect: LayoutRect
    /// The bar inflated by `LayoutMetrics.dividerHitSlop` — what a finger has to hit.
    public let hitRect: LayoutRect
    /// The rect being divided. Drag arithmetic needs its extent.
    public let parentRect: LayoutRect
    public let fraction: Double
    /// How far the fraction may travel before some tile drops below its minimum size.
    /// Precomputed here so no view ever has to think about clamping.
    public let fractionRange: ClosedRange<Double>

    public var isAdjustable: Bool {
        fractionRange.upperBound - fractionRange.lowerBound > LayoutSize.epsilon
    }
}

/// Where every tile and divider actually sits, for one canvas.
public struct LayoutSolution: Hashable, Sendable {
    public let canvas: LayoutRect
    /// Frames keyed by tile. Together with the gutters these tile the canvas exactly.
    public let paneRects: [PaneID: LayoutRect]
    /// Tiles in reading order, so the view layer can iterate deterministically.
    public let panes: [Pane]
    public let dividers: [SolvedDivider]

    public func rect(for paneID: PaneID) -> LayoutRect? {
        paneRects[paneID]
    }

    public func divider(_ id: DividerID) -> SolvedDivider? {
        dividers.first { $0.id == id }
    }
}

/// Turns a `LayoutTree` into concrete rectangles.
///
/// Kept separate from the tree so it can be exercised on synthetic canvases with no
/// views, no screen and no device — which is the only way any of this gets tested here.
public enum LayoutSolver {
    public static func solve(
        _ tree: LayoutTree,
        in canvas: LayoutRect,
        gutter: Double = LayoutMetrics.gutter,
        hitSlop: Double = LayoutMetrics.dividerHitSlop,
        policy: MinimumSizePolicy = .uniform
    ) -> LayoutSolution {
        var paneRects: [PaneID: LayoutRect] = [:]
        var dividers: [SolvedDivider] = []

        place(
            node: tree.root,
            in: canvas,
            gutter: gutter,
            hitSlop: hitSlop,
            policy: policy,
            paneRects: &paneRects,
            dividers: &dividers
        )

        return LayoutSolution(
            canvas: canvas,
            paneRects: paneRects,
            panes: tree.panes,
            dividers: dividers
        )
    }

    private static func place(
        node: LayoutNode,
        in rect: LayoutRect,
        gutter: Double,
        hitSlop: Double,
        policy: MinimumSizePolicy,
        paneRects: inout [PaneID: LayoutRect],
        dividers: inout [SolvedDivider]
    ) {
        switch node {
        case .pane(let pane):
            paneRects[pane.id] = rect

        case .split(let split):
            let range = fractionRange(for: split, in: rect, gutter: gutter, policy: policy)
            // The stored fraction is authoritative but advisory: a layout authored on a
            // roomier canvas can ask for a share that does not fit here, and the tile
            // minimums win. Nothing is written back — rotating the phone must not
            // silently rewrite the layout the user arranged.
            let fraction = range.clamp(split.fraction)

            let (first, second) = rect.divided(along: split.axis, fraction: fraction, gutter: gutter)
            let track = rect.dividerRect(along: split.axis, fraction: fraction, gutter: gutter)

            dividers.append(
                SolvedDivider(
                    id: split.id,
                    axis: split.axis,
                    trackRect: track,
                    hitRect: inflate(track, along: split.axis, by: hitSlop),
                    parentRect: rect,
                    fraction: fraction,
                    fractionRange: range
                )
            )

            place(node: split.first, in: first, gutter: gutter, hitSlop: hitSlop,
                  policy: policy, paneRects: &paneRects, dividers: &dividers)
            place(node: split.second, in: second, gutter: gutter, hitSlop: hitSlop,
                  policy: policy, paneRects: &paneRects, dividers: &dividers)
        }
    }

    /// How far this divider may move without starving either subtree.
    ///
    /// Derived from both children's minimum sizes, which are themselves a fold over
    /// their whole subtrees — so dragging a top-level divider correctly respects the
    /// minimum size of a tile nested two levels down.
    static func fractionRange(
        for split: Split,
        in rect: LayoutRect,
        gutter: Double,
        policy: MinimumSizePolicy
    ) -> ClosedRange<Double> {
        let usable = Swift.max(0, split.axis.extent(of: rect.size) - gutter)
        guard usable > LayoutSize.epsilon else { return 0.5...0.5 }

        let firstMinimum = LayoutTree.minimumSize(of: split.first, policy: policy, gutter: gutter)
        let secondMinimum = LayoutTree.minimumSize(of: split.second, policy: policy, gutter: gutter)

        let lower = split.axis.extent(of: firstMinimum) / usable
        let upper = 1 - split.axis.extent(of: secondMinimum) / usable

        // The canvas is too small for both minimums. Rather than produce an inverted
        // range, freeze the divider proportionally between the two demands — the tiles
        // are all too small either way, and a frozen divider is at least predictable.
        guard lower <= upper else {
            let total = split.axis.extent(of: firstMinimum) + split.axis.extent(of: secondMinimum)
            let midpoint = total > 0 ? split.axis.extent(of: firstMinimum) / total : 0.5
            let frozen = Split.clampToOpenUnitInterval(midpoint)
            return frozen...frozen
        }

        return Split.clampToOpenUnitInterval(lower)...Split.clampToOpenUnitInterval(upper)
    }

    private static func inflate(_ rect: LayoutRect, along axis: SplitAxis, by slop: Double) -> LayoutRect {
        switch axis {
        case .horizontal:
            return LayoutRect(
                x: rect.minX - slop,
                y: rect.minY,
                width: rect.width + slop * 2,
                height: rect.height
            )
        case .vertical:
            return LayoutRect(
                x: rect.minX,
                y: rect.minY - slop,
                width: rect.width,
                height: rect.height + slop * 2
            )
        }
    }
}

extension ClosedRange where Bound == Double {
    public func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
