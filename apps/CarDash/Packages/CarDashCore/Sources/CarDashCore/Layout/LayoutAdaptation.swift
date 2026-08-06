import Foundation

/// The result of fitting a layout to a canvas it was not authored for.
public struct AdaptedLayout: Hashable, Sendable {
    public var tree: LayoutTree
    /// Tiles that could not be kept at a usable size, in their original order. The UI
    /// shows these in a switcher rail rather than dropping them silently.
    public var overflow: [Pane]
    /// True when this was derived rather than authored, which the editor surfaces so the
    /// user knows why rearranging portrait does not stick.
    public var isDerived: Bool

    public init(tree: LayoutTree, overflow: [Pane] = [], isDerived: Bool = false) {
        self.tree = tree
        self.overflow = overflow
        self.isDerived = isDerived
    }
}

extension LayoutTree {
    /// Every split's axis turned through 90°.
    ///
    /// The whole adaptation for portrait, most of the time: a landscape dashboard is
    /// mostly side-by-side splits, and the same arrangement stacked vertically is
    /// usually exactly what a tall canvas wants.
    public func flippingAxes() -> LayoutTree {
        LayoutTree(root: Self.flippingAxes(in: root))
    }

    private static func flippingAxes(in node: LayoutNode) -> LayoutNode {
        guard case .split(var split) = node else { return node }
        split.axis = split.axis.perpendicular
        split.first = flippingAxes(in: split.first)
        split.second = flippingAxes(in: split.second)
        return .split(split)
    }

    /// Fits this layout to a canvas it was not authored for.
    ///
    /// Three steps, cheapest first: use it as-is if it fits; try it rotated; and only
    /// then start demoting tiles. Demotion removes the tile with the smallest minimum
    /// size first — the clock and the gauges go before the map does — and stops as soon
    /// as the rest fits.
    ///
    /// The deliberate outcome on a phone in portrait is usually one or two tiles plus a
    /// rail, not a squeezed 2×2. A grid of tiles too small to hit is worse than a
    /// switcher, particularly while moving.
    public func adapted(
        to canvasClass: CanvasClass,
        canvas: LayoutSize,
        policy: MinimumSizePolicy = .uniform,
        gutter: Double = LayoutMetrics.gutter
    ) -> AdaptedLayout {
        // The tree is fraction-based, so a bigger canvas of the same orientation needs
        // no adaptation at all.
        guard canvasClass == .phonePortrait else {
            return AdaptedLayout(tree: self, overflow: [], isDerived: false)
        }

        let flipped = flippingAxes()
        for candidate in [self, flipped]
        where canvas.canContain(candidate.minimumSize(policy: policy, gutter: gutter)) {
            return AdaptedLayout(tree: candidate, overflow: [], isDerived: candidate != self)
        }

        var working = shortfall(of: flipped, in: canvas, policy: policy, gutter: gutter)
            <= shortfall(of: self, in: canvas, policy: policy, gutter: gutter)
            ? flipped : self

        let originalOrder = paneIDs
        var demoted: [Pane] = []

        while working.paneCount > 1,
              !canvas.canContain(working.minimumSize(policy: policy, gutter: gutter)) {
            // Smallest minimum area first, and among equals the one furthest down the
            // reading order, so the result is deterministic and testable.
            guard let victim = working.panes.enumerated().min(by: { lhs, rhs in
                let lhsArea = policy(lhs.element.sectionID).area
                let rhsArea = policy(rhs.element.sectionID).area
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return lhs.offset > rhs.offset
            })?.element else { break }

            do {
                try working.remove(victim.id)
                demoted.append(victim)
            } catch {
                break
            }
        }

        // Present the rail in the order the tiles appeared in the authored layout, not
        // the order they happened to be evicted.
        demoted.sort { lhs, rhs in
            let lhsIndex = originalOrder.firstIndex(of: lhs.id) ?? .max
            let rhsIndex = originalOrder.firstIndex(of: rhs.id) ?? .max
            return lhsIndex < rhsIndex
        }

        return AdaptedLayout(tree: working, overflow: demoted, isDerived: true)
    }

    /// How many points short of fitting a layout is, summed over both axes.
    private func shortfall(
        of tree: LayoutTree,
        in canvas: LayoutSize,
        policy: MinimumSizePolicy,
        gutter: Double
    ) -> Double {
        let needed = tree.minimumSize(policy: policy, gutter: gutter)
        return Swift.max(0, needed.width - canvas.width) + Swift.max(0, needed.height - canvas.height)
    }
}
