import Foundation

/// How tightly the dashboard is packed.
///
/// A phone clamped to a windscreen has less usable glass than the same phone in a hand, and
/// every point spent on a gap or a corner arc is a point not spent on the thing being glanced
/// at. But the right amount of breathing room depends on the mount, the screen and the eyes
/// looking at it, which is not something to guess from a spec — so it is a setting.
///
/// All four values are here rather than scattered through the views because they have to agree.
/// The gutter feeds the layout solver, the corner radius feeds the tile chrome, and the padding
/// feeds every section; a corner radius larger than the padding clips content against the arc,
/// which is exactly the failure this type exists to make impossible to introduce by accident.
public enum DisplayDensity: String, Codable, Hashable, Sendable, CaseIterable {
    /// Roughly what a stock iOS app looks like.
    case cosy
    /// The default. Noticeably tighter than stock, still clearly separated tiles.
    case standard
    /// As tight as the touch targets allow.
    case compact

    public static let `default` = DisplayDensity.standard

    /// Gap between adjacent tiles, and the width of the divider drawn in it.
    public var gutter: Double {
        switch self {
        case .cosy: return 10
        case .standard: return 6
        case .compact: return 4
        }
    }

    /// Corner radius of a tile.
    public var paneCornerRadius: Double {
        switch self {
        case .cosy: return 16
        case .standard: return 10
        case .compact: return 8
        }
    }

    /// Inset from a tile's edge to its content.
    public var panePadding: Double {
        switch self {
        case .cosy: return 10
        case .standard: return 6
        case .compact: return 4
        }
    }

    /// Inset from the screen edge to the outermost tiles.
    ///
    /// Its own value rather than reusing `gutter`. They were the same number for the first five
    /// phases and doing two unrelated jobs, which meant tightening the gaps between tiles also
    /// pushed the dashboard away from the screen edge — the opposite of what was wanted.
    public var canvasInset: Double {
        switch self {
        case .cosy: return 10
        case .standard: return 6
        case .compact: return 4
        }
    }

    /// The smallest a divider's touch target may be, whatever the gutter shrinks to.
    public static let minimumDividerTarget: Double = 44

    /// How far beyond the visible divider a drag still counts.
    ///
    /// Derived rather than fixed, and this is the point of deriving it: a 4-point bar in a
    /// moving car is an unreasonable thing to hit, so as the gutter tightens the invisible
    /// target grows to compensate. The bar gets thinner; grabbing it does not get harder.
    public var dividerHitSlop: Double {
        max(17, (Self.minimumDividerTarget - gutter) / 2)
    }

    /// The total touch target across a divider — bar plus slop on both sides.
    public var dividerTarget: Double {
        gutter + dividerHitSlop * 2
    }

    // MARK: - Presentation

    public var title: String {
        switch self {
        case .cosy: return "Cosy"
        case .standard: return "Standard"
        case .compact: return "Compact"
        }
    }

    public var blurb: String {
        switch self {
        case .cosy: return "Generous gaps and rounded corners."
        case .standard: return "Tighter, with tiles still clearly apart."
        case .compact: return "Every point given to the tiles."
        }
    }
}
