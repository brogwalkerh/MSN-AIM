import Foundation
import Testing
import CarDashCore
@testable import CarDashKit

/// Checks the join between the layout engine, which knows only identifier strings, and
/// the registry, which knows what those strings render as.
///
/// The bug this exists for is quiet: rename a section, and every bundled preset still
/// loads, still lays out, and shows a placeholder tile where the map used to be. Nothing
/// throws, nothing logs, and it is only visible by looking at the screen.
@Suite("Section registry")
@MainActor
struct SectionRegistryTests {
    private let registry = SectionRegistry()

    @Test("Every section a bundled preset names is registered")
    func presetsResolve() {
        for preset in LayoutPresets.all {
            for sectionID in preset.tree().sectionIDs {
                #expect(
                    registry.descriptor(for: sectionID) != nil,
                    "preset \"\(preset.id)\" uses \(sectionID), which nothing registers"
                )
            }
        }
    }

    @Test("Every identifier declared in Core has a descriptor, and vice versa")
    func coreAndRegistryAgree() {
        let declared = Set(SectionID.builtIn)
        let registered = Set(registry.all.map(\.id))
        #expect(declared == registered, "declared \(declared) but registered \(registered)")
    }

    // The registry's minimum sizes feed the layout engine's fit checks, and Core's table
    // feeds the preset validation that runs on Linux. If the two disagreed, a preset
    // could pass its own test and still be refused at runtime.
    @Test("Registry minimums match the table the presets are checked against")
    func minimumSizesAgree() {
        let policy = registry.minimumSizePolicy
        for descriptor in registry.all {
            #expect(
                policy(descriptor.id) == SectionMetrics.minimumSize(for: descriptor.id),
                "\(descriptor.id) disagrees between the registry and SectionMetrics"
            )
        }
    }

    @Test("Every preset fits every reference canvas under the registry's own policy")
    func presetsFitUnderRegistryPolicy() {
        let policy = registry.minimumSizePolicy
        for preset in LayoutPresets.all {
            let needed = preset.tree().minimumSize(policy: policy)
            for canvas in ReferenceCanvas.allLandscape {
                #expect(canvas.canContain(needed), "\(preset.id) does not fit \(canvas.width)x\(canvas.height)")
            }
        }
    }

    @Test("Descriptors are complete enough to render a picker row")
    func descriptorsAreComplete() {
        for descriptor in registry.all {
            #expect(!descriptor.title.isEmpty)
            #expect(!descriptor.systemImage.isEmpty)
            #expect(!descriptor.blurb.isEmpty, "\(descriptor.id) has no description")
            #expect(descriptor.minimumSize.width > 0 && descriptor.minimumSize.height > 0)
        }
    }

    @Test("The picker leads with sections that actually do something")
    func pickerOrdersReadySectionsFirst() {
        let ready = registry.pickerOrder.prefix { !$0.isComingSoon }
        #expect(!ready.isEmpty)
        #expect(registry.pickerOrder.drop(while: { !$0.isComingSoon }).allSatisfy(\.isComingSoon))
    }

    @Test("An unknown identifier resolves to nothing rather than a wrong tile")
    func unknownSection() {
        #expect(registry.descriptor(for: "tirePressure") == nil)
        #expect(registry.title(for: "tirePressure") == "tirePressure")
    }

    @Test("Registering the same identifier twice replaces rather than duplicates")
    func reregistration() {
        let registry = SectionRegistry()
        let before = registry.all.count
        registry.register(
            SectionDescriptor(
                id: .clock,
                title: "Replacement",
                systemImage: "clock",
                blurb: "test"
            ) { _ in AnyView(EmptyView()) }
        )
        #expect(registry.all.count == before)
        #expect(registry.title(for: .clock) == "Replacement")
    }
}
