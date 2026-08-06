import Foundation

/// A point in the dashboard canvas coordinate space (origin top-left, y grows downward,
/// matching SwiftUI).
///
/// This exists instead of `CGPoint` because CoreGraphics is unavailable on Linux, and
/// this package must build and test there. See `Package.swift`.
public struct LayoutPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = LayoutPoint(x: 0, y: 0)

    public func offset(dx: Double = 0, dy: Double = 0) -> LayoutPoint {
        LayoutPoint(x: x + dx, y: y + dy)
    }

    /// The component along `axis` — used so layout math can be written once instead of
    /// twice with x/y swapped.
    public func component(_ axis: SplitAxis) -> Double {
        axis == .horizontal ? x : y
    }
}
