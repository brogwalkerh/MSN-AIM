import Foundation
import Testing
@testable import CarDashCore

@Suite("Presets")
struct LayoutPresetTests {
    private let policy = SectionMetrics.builtInPolicy

    // The failure this catches: a preset that looks fine in a diff but leaves the map
    // 40 points wide on the smallest supported phone. There is no simulator in this
    // project's development loop, so without this test that lands on the user's device.
    @Test("Every preset fits every landscape canvas the app supports")
    func presetsFitEveryCanvas() {
        for preset in LayoutPresets.all {
            let needed = preset.tree().minimumSize(policy: policy)
            for canvas in ReferenceCanvas.allLandscape {
                #expect(
                    canvas.canContain(needed),
                    """
                    preset "\(preset.id)" needs \(needed.width)×\(needed.height) but \
                    \(canvas.width)×\(canvas.height) is available
                    """
                )
            }
        }
    }

    @Test("Every preset stays within the phone's tile and nesting limits")
    func presetsRespectLimits() {
        for preset in LayoutPresets.all {
            let tree = preset.tree()
            #expect(tree.paneCount <= SplitLimits.phone.maxPanes, "\(preset.id) has too many tiles")
            #expect(tree.depth <= SplitLimits.phone.maxDepth, "\(preset.id) nests too deeply")
        }
    }

    // Catches the classic "renamed a section, presets silently broke" regression: the
    // preset would load, the tile would render a placeholder, and nothing would fail.
    @Test("Every preset names a section the app knows about")
    func presetsUseKnownSections() {
        let known = Set(SectionID.builtIn)
        for preset in LayoutPresets.all {
            for sectionID in preset.tree().sectionIDs {
                #expect(known.contains(sectionID), "preset \(preset.id) uses unknown section \(sectionID)")
            }
        }
    }

    @Test("Every built-in section declares a minimum size")
    func everySectionHasAMinimum() {
        for sectionID in SectionID.builtIn {
            #expect(
                SectionMetrics.minimumSizes[sectionID] != nil,
                "\(sectionID) falls back to the default minimum — declare one deliberately"
            )
        }
    }

    @Test("Instantiating a preset twice produces independent tiles")
    func presetsAreNotShared() {
        let first = LayoutPresets.quad
        let second = LayoutPresets.quad
        #expect(first != second, "two dashboards from one preset must not share identity")
        #expect(first.sectionIDs == second.sectionIDs)
        #expect(Set(first.paneIDs).isDisjoint(with: Set(second.paneIDs)))
    }

    @Test("Preset metadata is present and unique")
    func presetMetadata() {
        let ids = LayoutPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate preset id")
        for preset in LayoutPresets.all {
            #expect(!preset.name.isEmpty)
            #expect(!preset.systemImage.isEmpty)
            #expect(!preset.summary.isEmpty)
            #expect(LayoutPresets.preset(id: preset.id)?.id == preset.id)
        }
    }

    @Test("A document made from a preset is immediately usable")
    func presetDocument() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let document = LayoutPresets.default.document(now: now)

        #expect(document.schemaVersion == LayoutDocument.currentSchemaVersion)
        #expect(document.createdAt == now)
        #expect(document.modifiedAt == now)
        #expect(document.variants.phoneLandscape.paneCount >= 1)
    }
}
