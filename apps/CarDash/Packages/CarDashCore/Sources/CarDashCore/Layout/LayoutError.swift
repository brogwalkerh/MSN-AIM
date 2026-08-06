import Foundation

public enum LayoutError: Error, Hashable, Sendable {
    case paneNotFound(PaneID)
    case dividerNotFound(DividerID)
    /// A dashboard with no tiles has nothing to show and no way back, so the last tile
    /// is replaced rather than removed.
    case cannotRemoveLastPane
    /// Splitting would produce a tile smaller than one of the sections can use. Reported
    /// rather than silently allowed: a 40-point-wide map is not a degraded map, it is a
    /// broken one.
    case wouldNotFit(needed: LayoutSize, available: LayoutSize)
    case maximumPanesExceeded(limit: Int)
    case maximumDepthExceeded(limit: Int)
}

extension LayoutError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .paneNotFound(let id):
            return "no pane with id \(id)"
        case .dividerNotFound(let id):
            return "no divider with id \(id)"
        case .cannotRemoveLastPane:
            return "the last remaining pane cannot be removed"
        case .wouldNotFit(let needed, let available):
            return "needs \(needed.width)×\(needed.height), only \(available.width)×\(available.height) available"
        case .maximumPanesExceeded(let limit):
            return "a layout can hold at most \(limit) tiles on this screen"
        case .maximumDepthExceeded(let limit):
            return "splitting further would exceed the maximum nesting depth of \(limit)"
        }
    }
}
