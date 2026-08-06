import Foundation

/// The shape of screen a layout is being drawn on.
///
/// Rotation is handled as a *variant switch*, not a re-layout: each class gets its own
/// tree, and turning the phone swaps which one is showing. Animating a tree through a
/// 90° aspect change looks bad and is a rich source of jank; crossfading between two
/// correct layouts does not.
public enum CanvasClass: String, Codable, Sendable, Hashable, CaseIterable {
    /// The canonical case. The phone is in a landscape mount; this is the layout the
    /// user actually authors.
    case phoneLandscape
    /// Derived from the landscape layout unless explicitly authored. See
    /// `LayoutTree.adapted(to:)`.
    case phonePortrait
    /// iPad, or a large phone in landscape. Reuses the canonical tree unchanged — the
    /// tree is fraction-based, so it simply scales.
    case tabletWide

    /// Anything whose short edge is at least this wide gets the roomier limits.
    static let tabletShortEdge: Double = 700

    public static func classify(_ size: LayoutSize) -> CanvasClass {
        if Swift.min(size.width, size.height) >= tabletShortEdge {
            return .tabletWide
        }
        return size.width >= size.height ? .phoneLandscape : .phonePortrait
    }

    public var splitLimits: SplitLimits {
        SplitLimits.forCanvas(self)
    }
}
