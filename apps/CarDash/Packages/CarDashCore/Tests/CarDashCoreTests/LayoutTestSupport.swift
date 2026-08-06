import Foundation
import Testing
@testable import CarDashCore

// MARK: - Fixtures

enum Fixture {
    enum Error: Swift.Error { case missing(String) }

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw Error.missing(name)
        }
        return try Data(contentsOf: url)
    }
}

// MARK: - Deterministic randomness

/// xorshift64. Seeded and reproducible, so a property-test failure can be re-run
/// verbatim from the seed printed in the failure message — which matters more than usual
/// here, because these tests are the only place the layout engine is ever exercised.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Any nonzero state works; xorshift is stuck at zero.
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x9E3779B97F4A7C15 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Random layouts

enum RandomLayout {
    static let sections: [SectionID] = [.map, .music, .gauges, .weather, .clock, .nowPlaying]

    /// Builds a layout by applying a random sequence of the operations the editor
    /// exposes. Uses generous limits and a large canvas so the shapes stay varied;
    /// individual tests re-check fit against whatever canvas they care about.
    static func tree(
        seed: UInt64,
        operations: Int = 12,
        limits: SplitLimits = .init(maxPanes: 8, maxDepth: 5)
    ) -> (tree: LayoutTree, log: [String]) {
        var generator = SeededGenerator(seed: seed)
        var tree = LayoutTree(sections.randomElement(using: &generator)!)
        var log: [String] = ["start \(tree.panes[0].sectionID)"]

        for _ in 0..<operations {
            let panes = tree.panes
            switch Int.random(in: 0..<10, using: &generator) {
            case 0..<5:
                guard let target = panes.randomElement(using: &generator) else { continue }
                let axis = Bool.random(using: &generator) ? SplitAxis.horizontal : .vertical
                let section = sections.randomElement(using: &generator)!
                if let id = try? tree.split(
                    target.id,
                    axis: axis,
                    inserting: section,
                    fraction: Double.random(in: 0.2...0.8, using: &generator),
                    limits: limits
                ) {
                    log.append("split \(target.id) \(axis) -> \(section) (\(id))")
                }

            case 5..<7:
                guard let target = panes.randomElement(using: &generator) else { continue }
                if (try? tree.remove(target.id)) != nil {
                    log.append("remove \(target.id)")
                }

            case 7..<8:
                guard panes.count >= 2,
                      let a = panes.randomElement(using: &generator),
                      let b = panes.randomElement(using: &generator) else { continue }
                if (try? tree.exchange(a.id, b.id)) != nil {
                    log.append("exchange \(a.id) \(b.id)")
                }

            case 8..<9:
                guard let target = panes.randomElement(using: &generator) else { continue }
                let section = sections.randomElement(using: &generator)!
                if (try? tree.replace(target.id, with: section)) != nil {
                    log.append("replace \(target.id) -> \(section)")
                }

            default:
                guard let divider = tree.splits.randomElement(using: &generator) else { continue }
                let fraction = Double.random(in: 0.05...0.95, using: &generator)
                if (try? tree.setFraction(divider.id, to: fraction)) != nil {
                    log.append("fraction \(divider.id) -> \(fraction)")
                }
            }
        }

        return (tree, log)
    }
}

// MARK: - Invariants

enum LayoutInvariant {
    /// Asserts the solved layout tiles its canvas exactly: no overlaps, nothing outside
    /// the canvas, and every square point accounted for by either a tile or a divider.
    ///
    /// The area identity is the strong one. Panes and dividers partition the canvas by
    /// construction, so any bug in the solver's arithmetic — a gutter counted twice, a
    /// fraction applied to the wrong extent — shows up as a mismatch here.
    static func tilesExactly(
        _ solution: LayoutSolution,
        _ comment: @autoclosure () -> String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rects = solution.panes.compactMap { solution.paneRects[$0.id] }

        #expect(
            rects.count == solution.panes.count,
            "every pane needs a rect. \(comment())",
            sourceLocation: sourceLocation
        )

        for rect in rects {
            #expect(rect.width >= 0 && rect.height >= 0, "negative extent. \(comment())",
                    sourceLocation: sourceLocation)
            #expect(
                rect.minX >= solution.canvas.minX - LayoutSize.epsilon
                    && rect.minY >= solution.canvas.minY - LayoutSize.epsilon
                    && rect.maxX <= solution.canvas.maxX + LayoutSize.epsilon
                    && rect.maxY <= solution.canvas.maxY + LayoutSize.epsilon,
                "pane escapes the canvas. \(comment())",
                sourceLocation: sourceLocation
            )
        }

        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                #expect(!rect.intersects(other), "panes overlap. \(comment())",
                        sourceLocation: sourceLocation)
            }
        }

        let paneArea = rects.reduce(0) { $0 + $1.area }
        let dividerArea = solution.dividers.reduce(0) { $0 + $1.trackRect.area }
        let accounted = paneArea + dividerArea
        #expect(
            abs(accounted - solution.canvas.area) < 1e-6 * Swift.max(1, solution.canvas.area),
            """
            panes + dividers should exactly cover the canvas: \
            \(accounted) vs \(solution.canvas.area). \(comment())
            """,
            sourceLocation: sourceLocation
        )
    }

    /// Asserts no tile was drawn smaller than its section can use.
    static func respectsMinimums(
        _ solution: LayoutSolution,
        policy: MinimumSizePolicy,
        _ comment: @autoclosure () -> String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for pane in solution.panes {
            guard let rect = solution.paneRects[pane.id] else { continue }
            let minimum = policy(pane.sectionID)
            #expect(
                rect.size.canContain(minimum),
                """
                \(pane.sectionID) got \(rect.width)×\(rect.height), \
                needs \(minimum.width)×\(minimum.height). \(comment())
                """,
                sourceLocation: sourceLocation
            )
        }
    }
}
