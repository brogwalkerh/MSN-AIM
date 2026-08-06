import Foundation
import Testing
@testable import CarDashCore

@Suite("Portrait adaptation")
struct LayoutAdaptationTests {
    private let policy = SectionMetrics.builtInPolicy
    private let portrait = ReferenceCanvas.phonePortrait

    @Test("Landscape and tablet canvases use the authored tree untouched")
    func nonPortraitIsPassedThrough() {
        let tree = LayoutPresets.quad
        for canvasClass in [CanvasClass.phoneLandscape, .tabletWide] {
            let adapted = tree.adapted(to: canvasClass, canvas: ReferenceCanvas.tablet, policy: policy)
            #expect(adapted.tree == tree)
            #expect(adapted.overflow.isEmpty)
            #expect(!adapted.isDerived)
        }
    }

    @Test("Flipping the axes is tried before anything is dropped")
    func rotationBeforeDemotion() {
        // Map beside gauges needs 460 points of width — more than a portrait phone has.
        // Stacked, it needs 340 points of height, which it has plenty of.
        var tree = LayoutTree(.map)
        let map = tree.panes[0].id
        _ = try? tree.split(map, axis: .horizontal, inserting: .gauges)

        let adapted = tree.adapted(to: .phonePortrait, canvas: portrait, policy: policy)

        #expect(adapted.overflow.isEmpty, "nothing needed to be demoted")
        #expect(adapted.isDerived)
        #expect(adapted.tree.paneCount == 2)
        #expect(adapted.tree.splits.first?.axis == .vertical, "should have been stacked")
        #expect(portrait.canContain(adapted.tree.minimumSize(policy: policy)))
    }

    @Test("A layout that already fits portrait is left alone")
    func noChangeWhenItAlreadyFits() {
        let tree = LayoutPresets.mapOnly
        let adapted = tree.adapted(to: .phonePortrait, canvas: portrait, policy: policy)
        #expect(adapted.tree == tree)
        #expect(adapted.overflow.isEmpty)
        #expect(!adapted.isDerived)
    }

    @Test("Every preset adapts to a portrait phone without leaving an unusable tile")
    func everyPresetAdapts() {
        for preset in LayoutPresets.all {
            let adapted = preset.tree().adapted(to: .phonePortrait, canvas: portrait, policy: policy)

            #expect(adapted.tree.paneCount >= 1, "\(preset.id) adapted to nothing")
            #expect(
                portrait.canContain(adapted.tree.minimumSize(policy: policy))
                    || adapted.tree.paneCount == 1,
                "\(preset.id) still does not fit after adaptation"
            )

            let solution = LayoutSolver.solve(
                adapted.tree,
                in: LayoutRect(origin: .zero, size: portrait),
                policy: policy
            )
            LayoutInvariant.tilesExactly(solution, preset.id)
        }
    }

    @Test("Demoted tiles are kept, not dropped")
    func overflowPreservesEverything() {
        let original = LayoutPresets.quad
        let adapted = original.adapted(to: .phonePortrait, canvas: portrait, policy: policy)

        let kept = Set(adapted.tree.paneIDs)
        let demoted = Set(adapted.overflow.map(\.id))
        #expect(kept.isDisjoint(with: demoted))
        #expect(kept.union(demoted) == Set(original.paneIDs), "a tile went missing entirely")
    }

    // The four-up preset is the interesting case: it cannot fit portrait in either
    // orientation, so it exercises the demotion path. The map is the biggest and most
    // important tile, and the rule "demote the smallest minimum first" is what keeps it.
    @Test("Demotion sheds the small tiles and keeps the map")
    func demotionKeepsTheImportantTile() {
        let adapted = LayoutPresets.quad.adapted(to: .phonePortrait, canvas: portrait, policy: policy)

        #expect(!adapted.overflow.isEmpty)
        #expect(adapted.tree.sectionIDs.contains(.map))
        #expect(adapted.overflow.contains { $0.sectionID == .gauges })
        #expect(portrait.canContain(adapted.tree.minimumSize(policy: policy)))
    }

    @Test("The overflow rail is in the authored reading order, not eviction order")
    func overflowOrdering() {
        let original = LayoutPresets.quad
        let adapted = original.adapted(to: .phonePortrait, canvas: portrait, policy: policy)

        let authoredOrder = original.paneIDs
        let overflowIndices = adapted.overflow.compactMap { authoredOrder.firstIndex(of: $0.id) }
        #expect(overflowIndices == overflowIndices.sorted())
    }

    @Test("Adaptation is deterministic")
    func deterministic() {
        let tree = LayoutPresets.quad
        let first = tree.adapted(to: .phonePortrait, canvas: portrait, policy: policy)
        let second = tree.adapted(to: .phonePortrait, canvas: portrait, policy: policy)
        #expect(first == second)
    }

    @Test("Adaptation always terminates, however hostile the canvas",
          arguments: 0..<64 as Range<UInt64>)
    func alwaysTerminates(seed: UInt64) {
        let (tree, log) = RandomLayout.tree(seed: seed, operations: 16)
        // Absurdly small: nothing can fit, so demotion runs until one tile is left.
        let cramped = LayoutSize(width: 120, height: 200)
        let adapted = tree.adapted(to: .phonePortrait, canvas: cramped, policy: policy)

        #expect(adapted.tree.paneCount >= 1, "seed \(seed): \(log.joined(separator: "; "))")
        #expect(
            adapted.tree.paneCount + adapted.overflow.count == tree.paneCount,
            "seed \(seed): tiles were lost"
        )
    }

    // MARK: - Document-level

    @Test("An authored portrait variant wins over a derived one")
    func authoredVariantWins() {
        let authored = LayoutPresets.mapOnly
        let document = LayoutDocument(
            name: "Custom",
            variants: LayoutVariants(phoneLandscape: LayoutPresets.quad, phonePortrait: authored),
            createdAt: .distantPast,
            modifiedAt: .distantPast
        )

        let result = document.layout(for: .phonePortrait, canvas: portrait, policy: policy)
        #expect(result.tree == authored)
        #expect(!result.isDerived)
        #expect(result.overflow.isEmpty)
    }

    @Test("With no authored variant, portrait is derived from landscape")
    func derivesWhenAbsent() {
        let document = LayoutDocument(
            name: "Custom",
            variants: LayoutVariants(phoneLandscape: LayoutPresets.quad),
            createdAt: .distantPast,
            modifiedAt: .distantPast
        )

        let result = document.layout(for: .phonePortrait, canvas: portrait, policy: policy)
        #expect(result.isDerived)
        #expect(result.tree != LayoutPresets.quad)
    }
}
