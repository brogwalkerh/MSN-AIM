import Foundation

/// The direction in which a split places its two children.
///
/// The naming here is the one thing in the layout engine most likely to be misread, so
/// it is worth being exact: the case describes **how the children are arranged**, not
/// which way the divider bar runs. They are perpendicular.
///
/// ```
/// .horizontal          .vertical
/// ┌─────┬─────┐        ┌───────────┐
/// │first│secnd│        │   first   │
/// │     │     │        ├───────────┤
/// │     │     │        │  second   │
/// └─────┴─────┘        └───────────┘
///  divider is           divider is
///  a vertical bar       a horizontal bar
/// ```
public enum SplitAxis: String, Codable, Sendable, Hashable, CaseIterable {
    /// Children sit side by side along the x axis. The divider is a vertical bar.
    case horizontal
    /// Children are stacked along the y axis. The divider is a horizontal bar.
    case vertical

    /// The axis a divider bar is drawn along — always perpendicular to the layout axis.
    public var perpendicular: SplitAxis {
        self == .horizontal ? .vertical : .horizontal
    }

    /// The component of `size` that the two children divide between them.
    public func extent(of size: LayoutSize) -> Double {
        self == .horizontal ? size.width : size.height
    }

    /// The component of `size` that both children receive in full.
    public func crossExtent(of size: LayoutSize) -> Double {
        self == .horizontal ? size.height : size.width
    }

    /// Builds a size from an extent along this axis and an extent across it.
    public func size(extent: Double, crossExtent: Double) -> LayoutSize {
        self == .horizontal
            ? LayoutSize(width: extent, height: crossExtent)
            : LayoutSize(width: crossExtent, height: extent)
    }
}
