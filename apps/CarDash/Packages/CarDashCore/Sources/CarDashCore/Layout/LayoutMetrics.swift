import Foundation

/// Fixed spatial constants shared by the layout engine and the views that draw it.
public enum LayoutMetrics {
    /// Gap between adjacent tiles, and the width of the divider that lives in it.
    public static let gutter: Double = 10

    /// How far beyond the visible divider a drag still counts.
    ///
    /// A 10-point bar is a fine thing to look at and an unreasonable thing to hit in a
    /// moving car, so the touch target is inflated to roughly 44 points total without
    /// making the visual any heavier.
    public static let dividerHitSlop: Double = 17

    /// Corner radius of a tile.
    public static let paneCornerRadius: Double = 18
}

/// Ceilings on how far a layout may be subdivided.
///
/// Not a technical limit — the tree handles arbitrary depth. It is an ergonomic one: a
/// phone screen divided more than this produces tiles too small to read at a glance,
/// which in a car is worse than not having the tile at all.
public struct SplitLimits: Hashable, Sendable {
    public var maxPanes: Int
    public var maxDepth: Int

    public init(maxPanes: Int, maxDepth: Int) {
        self.maxPanes = maxPanes
        self.maxDepth = maxDepth
    }

    public static let phone = SplitLimits(maxPanes: 4, maxDepth: 3)
    public static let tablet = SplitLimits(maxPanes: 6, maxDepth: 4)
    public static let unlimited = SplitLimits(maxPanes: .max, maxDepth: .max)

    public static func forCanvas(_ canvasClass: CanvasClass) -> SplitLimits {
        switch canvasClass {
        case .tabletWide: return .tablet
        case .phoneLandscape, .phonePortrait: return .phone
        }
    }
}
