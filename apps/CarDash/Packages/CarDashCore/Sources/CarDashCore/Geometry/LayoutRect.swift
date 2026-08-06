import Foundation

/// A rectangle in the dashboard canvas coordinate space.
///
/// Stands in for `CGRect`, which does not exist on Linux. See `Package.swift`.
public struct LayoutRect: Codable, Hashable, Sendable {
    public var origin: LayoutPoint
    public var size: LayoutSize

    public init(origin: LayoutPoint, size: LayoutSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: width, height: height))
    }

    public static let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var width: Double { size.width }
    public var height: Double { size.height }
    public var area: Double { size.area }

    public var center: LayoutPoint {
        LayoutPoint(x: minX + width / 2, y: minY + height / 2)
    }

    /// The rect's start coordinate along `axis` (its left edge or its top edge).
    public func start(_ axis: SplitAxis) -> Double {
        axis == .horizontal ? minX : minY
    }

    /// Overlap test used by the tiling invariant checks. Shared edges do not count as
    /// intersection — adjacent tiles touch by design.
    public func intersects(_ other: LayoutRect) -> Bool {
        let e = LayoutSize.epsilon
        return minX < other.maxX - e && other.minX < maxX - e
            && minY < other.maxY - e && other.minY < maxY - e
    }

    public func inset(by amount: Double) -> LayoutRect {
        LayoutRect(
            x: minX + amount,
            y: minY + amount,
            width: Swift.max(0, width - amount * 2),
            height: Swift.max(0, height - amount * 2)
        )
    }

    /// Divides the rect into two along `axis`, giving the first child `fraction` of the
    /// available extent, and reserving `gutter` points between them for the divider.
    ///
    /// The gutter is removed from the *available* extent before the fraction is applied,
    /// so `fraction` always means "share of the usable space", not "share of the rect".
    /// Without that, a 0.5 split of a rect with a gutter would give the two children
    /// unequal sizes — a subtle asymmetry that is very hard to spot by eye and trivial
    /// to catch in a test.
    public func divided(along axis: SplitAxis, fraction: Double, gutter: Double) -> (first: LayoutRect, second: LayoutRect) {
        let total = axis.extent(of: size)
        let usable = Swift.max(0, total - gutter)
        let firstExtent = usable * fraction
        let secondExtent = usable - firstExtent
        let cross = axis.crossExtent(of: size)

        switch axis {
        case .horizontal:
            return (
                LayoutRect(x: minX, y: minY, width: firstExtent, height: cross),
                LayoutRect(x: minX + firstExtent + gutter, y: minY, width: secondExtent, height: cross)
            )
        case .vertical:
            return (
                LayoutRect(x: minX, y: minY, width: cross, height: firstExtent),
                LayoutRect(x: minX, y: minY + firstExtent + gutter, width: cross, height: secondExtent)
            )
        }
    }

    /// The divider bar's own rect between the two halves of `divided(along:fraction:gutter:)`.
    public func dividerRect(along axis: SplitAxis, fraction: Double, gutter: Double) -> LayoutRect {
        let usable = Swift.max(0, axis.extent(of: size) - gutter)
        let firstExtent = usable * fraction
        let cross = axis.crossExtent(of: size)

        switch axis {
        case .horizontal:
            return LayoutRect(x: minX + firstExtent, y: minY, width: gutter, height: cross)
        case .vertical:
            return LayoutRect(x: minX, y: minY + firstExtent, width: cross, height: gutter)
        }
    }
}
