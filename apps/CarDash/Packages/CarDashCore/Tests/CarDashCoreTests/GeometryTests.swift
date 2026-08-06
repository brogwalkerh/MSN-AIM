import Testing
@testable import CarDashCore

@Suite("Geometry")
struct GeometryTests {
    @Test("SplitAxis extent and cross-extent pick the right components")
    func axisComponents() {
        let size = LayoutSize(width: 800, height: 400)
        #expect(SplitAxis.horizontal.extent(of: size) == 800)
        #expect(SplitAxis.horizontal.crossExtent(of: size) == 400)
        #expect(SplitAxis.vertical.extent(of: size) == 400)
        #expect(SplitAxis.vertical.crossExtent(of: size) == 800)
        #expect(SplitAxis.horizontal.perpendicular == .vertical)
    }

    @Test("A round-trip through size(extent:crossExtent:) is lossless", arguments: SplitAxis.allCases)
    func axisSizeRoundTrip(axis: SplitAxis) {
        let original = LayoutSize(width: 640, height: 360)
        let rebuilt = axis.size(
            extent: axis.extent(of: original),
            crossExtent: axis.crossExtent(of: original)
        )
        #expect(rebuilt == original)
    }

    // The gutter is taken off the top before the fraction is applied. If it were not,
    // an even split would hand the two children different sizes.
    @Test("An even split with a gutter produces two equal children", arguments: SplitAxis.allCases)
    func evenSplitIsSymmetric(axis: SplitAxis) {
        let rect = LayoutRect(x: 0, y: 0, width: 852, height: 393)
        let (first, second) = rect.divided(along: axis, fraction: 0.5, gutter: 8)
        #expect(abs(axis.extent(of: first.size) - axis.extent(of: second.size)) < LayoutSize.epsilon)
    }

    @Test("Children plus gutter exactly reconstitute the parent", arguments: SplitAxis.allCases)
    func splitConservesExtent(axis: SplitAxis) {
        let rect = LayoutRect(x: 12, y: 30, width: 852, height: 393)
        let gutter = 8.0
        let (first, second) = rect.divided(along: axis, fraction: 0.37, gutter: gutter)
        let total = axis.extent(of: first.size) + gutter + axis.extent(of: second.size)
        #expect(abs(total - axis.extent(of: rect.size)) < LayoutSize.epsilon)
        // Both children span the full cross axis.
        #expect(axis.crossExtent(of: first.size) == axis.crossExtent(of: rect.size))
        #expect(axis.crossExtent(of: second.size) == axis.crossExtent(of: rect.size))
    }

    @Test("Split children never overlap, and the divider sits between them", arguments: SplitAxis.allCases)
    func splitChildrenAreDisjoint(axis: SplitAxis) {
        let rect = LayoutRect(x: 0, y: 0, width: 1000, height: 600)
        let (first, second) = rect.divided(along: axis, fraction: 0.6, gutter: 10)
        #expect(!first.intersects(second))

        let divider = rect.dividerRect(along: axis, fraction: 0.6, gutter: 10)
        #expect(divider.start(axis) >= first.start(axis) + axis.extent(of: first.size) - LayoutSize.epsilon)
        #expect(divider.start(axis) + 10 <= second.start(axis) + LayoutSize.epsilon)
    }

    @Test("Adjacent rects that merely touch do not count as intersecting")
    func touchingIsNotIntersecting() {
        let left = LayoutRect(x: 0, y: 0, width: 100, height: 100)
        let right = LayoutRect(x: 100, y: 0, width: 100, height: 100)
        #expect(!left.intersects(right))
        #expect(left.intersects(LayoutRect(x: 99, y: 0, width: 100, height: 100)))
    }

    @Test("canContain tolerates floating-point noise from repeated division")
    func canContainIsEpsilonTolerant() {
        let available = LayoutSize(width: 200 - 1e-12, height: 100)
        #expect(available.canContain(LayoutSize(width: 200, height: 100)))
        #expect(!available.canContain(LayoutSize(width: 201, height: 100)))
    }
}
