import CoreGraphics
import CarDashCore

// CarDashCore has its own geometry types so it can build and be tested on Linux, where
// CoreGraphics does not exist. This is the one place the two meet.

extension LayoutSize {
    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

extension LayoutPoint {
    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

extension LayoutRect {
    public var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}
