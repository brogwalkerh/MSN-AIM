import Foundation

/// A width/height pair in canvas points.
///
/// Stands in for `CGSize`, which does not exist on Linux. See `Package.swift`.
public struct LayoutSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = LayoutSize(width: 0, height: 0)

    /// Fallback minimum for a section that does not declare one, and the floor below
    /// which a tile stops being usable in a moving car at all.
    public static let `default` = LayoutSize(width: 160, height: 120)

    public var area: Double { width * height }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Whether a pane of `self` can accommodate something needing `other`.
    ///
    /// Uses a small epsilon because minimum sizes are compared against fractions of a
    /// canvas, and exact equality on accumulated floating-point division would reject
    /// layouts that are correct to any meaningful precision.
    public func canContain(_ other: LayoutSize) -> Bool {
        width >= other.width - Self.epsilon && height >= other.height - Self.epsilon
    }

    /// Component-wise maximum — the minimum size of two things placed on top of each
    /// other, and the "across the axis" half of a split's minimum-size fold.
    public func max(_ other: LayoutSize) -> LayoutSize {
        LayoutSize(
            width: Swift.max(width, other.width),
            height: Swift.max(height, other.height)
        )
    }

    public static let epsilon = 1e-6
}
