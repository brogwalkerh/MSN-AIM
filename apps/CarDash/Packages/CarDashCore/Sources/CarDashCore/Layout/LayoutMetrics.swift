import Foundation

/// The spatial constants, at the default density.
///
/// These exist as the default arguments of the Core layout functions, so that a caller with no
/// opinion gets a sensible arrangement. Anything that draws the real dashboard should pass the
/// user's chosen `DisplayDensity` instead — see `DisplayDensity` for why the numbers vary and
/// why they have to agree with each other.
public enum LayoutMetrics {
    /// Gap between adjacent tiles, and the width of the divider that lives in it.
    public static var gutter: Double { DisplayDensity.default.gutter }

    /// How far beyond the visible divider a drag still counts, inflating the touch target
    /// to at least `DisplayDensity.minimumDividerTarget` without making the bar any heavier.
    public static var dividerHitSlop: Double { DisplayDensity.default.dividerHitSlop }

    /// Corner radius of a tile.
    public static var paneCornerRadius: Double { DisplayDensity.default.paneCornerRadius }
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
