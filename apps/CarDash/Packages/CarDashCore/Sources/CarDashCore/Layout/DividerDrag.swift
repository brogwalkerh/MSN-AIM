import Foundation

/// The arithmetic of dragging one divider.
///
/// Small enough to look not worth extracting, and extracted anyway: it is the piece most
/// likely to be subtly wrong, and the only way to catch that here is a unit test.
///
/// The important property is that the fraction is computed **absolutely**, from the
/// gesture's total translation against the fraction the drag started at — never
/// incrementally from the current fraction. Incremental accumulation is the natural way
/// to write this and it is wrong: once a drag pushes past a clamp, every further event
/// adds to a value that is no longer where the finger is, so dragging back does not
/// return the divider to where it was. Absolute arithmetic makes over-dragging free.
public struct DividerDrag: Hashable, Sendable {
    public let dividerID: DividerID
    public let axis: SplitAxis
    /// The fraction when the gesture began.
    public let startFraction: Double
    /// The parent's extent along the axis, minus the gutter — the distance one full unit
    /// of fraction corresponds to.
    public let usableExtent: Double
    public let range: ClosedRange<Double>

    public init(
        dividerID: DividerID,
        axis: SplitAxis,
        startFraction: Double,
        usableExtent: Double,
        range: ClosedRange<Double>
    ) {
        self.dividerID = dividerID
        self.axis = axis
        self.startFraction = startFraction
        self.usableExtent = usableExtent
        self.range = range
    }

    public init(divider: SolvedDivider, gutter: Double = LayoutMetrics.gutter) {
        self.init(
            dividerID: divider.id,
            axis: divider.axis,
            startFraction: divider.fraction,
            usableExtent: Swift.max(0, divider.axis.extent(of: divider.parentRect.size) - gutter),
            range: divider.fractionRange
        )
    }

    /// The fraction for a gesture that has moved `translation` points from where it
    /// started, measured along this divider's axis.
    public func fraction(forTranslation translation: Double) -> Double {
        guard usableExtent > LayoutSize.epsilon else { return startFraction }
        let unclamped = startFraction + translation / usableExtent
        guard unclamped.isFinite else { return startFraction }
        return range.clamp(unclamped)
    }

    /// The translation along this divider's axis from a two-dimensional gesture. A
    /// horizontal split moves with x, a vertical one with y; the other component is
    /// simply ignored rather than projected, so a sloppy diagonal drag still does the
    /// obvious thing.
    public func translation(fromDX dx: Double, dy: Double) -> Double {
        axis == .horizontal ? dx : dy
    }

    /// True once the drag is pinned against an end of its range — the cue for the view
    /// to stop following the finger and fire a haptic tick.
    public func isClamped(atTranslation translation: Double) -> Bool {
        guard usableExtent > LayoutSize.epsilon else { return true }
        let unclamped = startFraction + translation / usableExtent
        return unclamped < range.lowerBound - LayoutSize.epsilon
            || unclamped > range.upperBound + LayoutSize.epsilon
    }
}
