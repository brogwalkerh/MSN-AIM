import Foundation
import Testing
@testable import CarDashCore

@Suite("Layout persistence")
struct LayoutPersistenceTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01Z

    @Test("Documents survive a round trip", arguments: 0..<64 as Range<UInt64>)
    func roundTrip(seed: UInt64) throws {
        let (tree, log) = RandomLayout.tree(seed: seed)
        let document = LayoutDocument(
            name: "Seed \(seed)",
            variants: LayoutVariants(
                phoneLandscape: tree,
                phonePortrait: RandomLayout.tree(seed: seed &+ 1).tree
            ),
            createdAt: referenceDate,
            modifiedAt: referenceDate
        )

        let decoded = try LayoutCodec.decode(LayoutCodec.encode(document))
        #expect(decoded == document, "seed \(seed): \(log.joined(separator: "; "))")
    }

    @Test("Section state survives verbatim")
    func stateRoundTrip() throws {
        struct Settings: Codable, Equatable { var units: String; var showTraffic: Bool }
        let settings = Settings(units: "mph", showTraffic: true)

        var tree = LayoutTree(.map)
        let id = try #require(tree.panes.first).id
        try tree.setState(.encoding(settings), for: id)

        let document = LayoutDocument(name: "S", tree: tree, now: referenceDate)
        let decoded = try LayoutCodec.decode(LayoutCodec.encode(document))

        let pane = try #require(decoded.variants.phoneLandscape.pane(id))
        #expect(pane.state.decoded(as: Settings.self) == settings)
    }

    @Test("Encoding is stable, so saving an unchanged document rewrites nothing")
    func encodingIsStable() throws {
        let document = LayoutPresets.default.document(now: referenceDate)
        let once = try LayoutCodec.encode(document)
        let twice = try LayoutCodec.encode(LayoutCodec.decode(once))
        #expect(once == twice)
    }

    // A committed fixture is decoded rather than compared byte for byte. Byte comparison
    // would additionally catch encoder-setting drift, but it fails on things nobody
    // cares about — a Foundation change to double formatting, say. Decoding an old file
    // is what actually protects the thing that matters: renaming a coding key, or
    // changing the shape of the tree, breaks this test loudly.
    @Test("The committed v1 fixture still decodes")
    func decodesV1Fixture() throws {
        let document = try LayoutCodec.decode(Fixture.data("layout-v1"))

        #expect(document.schemaVersion == 1)
        #expect(document.name == "Navigation")
        #expect(document.id == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))

        let tree = document.variants.phoneLandscape
        #expect(tree.sectionIDs == [.map, .music, .gauges])
        #expect(tree.paneCount == 3)
        #expect(tree.splits.count == 2)
        #expect(tree.splits[0].axis == .horizontal)
        #expect(tree.splits[0].fraction == 0.66)
        #expect(tree.splits[1].axis == .vertical)

        #expect(document.variants.phonePortrait == nil)
        #expect(document.variants.tabletWide == nil)
    }

    // The forward-compatibility promise. A layout saved by a build that had a section
    // this build does not must still load — the unknown tile renders a placeholder with
    // a "replace this" button. Failing the whole document would lose the user's entire
    // dashboard over one tile.
    @Test("A document naming an unknown section still decodes")
    func unknownSectionSurvives() throws {
        let document = try LayoutCodec.decode(Fixture.data("layout-unknown-section"))
        let tree = document.variants.phoneLandscape

        #expect(tree.paneCount == 2)
        #expect(tree.sectionIDs.contains("tirePressure"))

        // And its opaque state is preserved, so downgrading and upgrading again does not
        // silently destroy that section's settings.
        let pane = try #require(tree.panes.last)
        #expect(!pane.state.isEmpty)
        let reEncoded = try LayoutCodec.decode(LayoutCodec.encode(document))
        #expect(reEncoded.variants.phoneLandscape.panes.last?.state == pane.state)
    }

    @Test("A document from a future build is refused, not misread")
    func futureVersionRefused() throws {
        var json = try #require(
            String(data: Fixture.data("layout-v1"), encoding: .utf8)
        )
        json = json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")

        #expect(throws: LayoutMigrator.MigrationError.unsupportedFutureVersion(found: 99, supported: 1)) {
            try LayoutCodec.decode(Data(json.utf8))
        }
    }

    @Test("Garbage is reported as malformed rather than crashing")
    func malformedInput() {
        #expect(throws: (any Error).self) {
            try LayoutCodec.decode(Data("not json".utf8))
        }
        #expect(throws: (any Error).self) {
            try LayoutCodec.decode(Data(#"{"schemaVersion": 1}"#.utf8))
        }
    }

    // MARK: - Store

    @Test("An empty store is seeded with the presets on first launch")
    func seedsOnFirstLaunch() throws {
        let store = InMemoryLayoutStore()
        let (documents, activeID) = try store.loadOrSeed(now: referenceDate)

        #expect(documents.count == LayoutPresets.all.count)
        #expect(documents.contains { $0.id == activeID })
        #expect(store.loadActiveID() == activeID)
    }

    @Test("A second launch reuses what is already stored")
    func doesNotReseed() throws {
        let store = InMemoryLayoutStore()
        let first = try store.loadOrSeed(now: referenceDate)
        let second = try store.loadOrSeed(now: referenceDate)

        #expect(first.documents.map(\.id) == second.documents.map(\.id))
        #expect(first.activeID == second.activeID)
    }

    @Test("A stale active id falls back to a document that exists")
    func staleActiveIDRecovers() throws {
        let store = InMemoryLayoutStore()
        _ = try store.loadOrSeed(now: referenceDate)
        store.setActiveID(UUID())

        let (documents, activeID) = try store.loadOrSeed(now: referenceDate)
        #expect(documents.contains { $0.id == activeID })
    }

    @Test("Deleting the active document moves the selection")
    func deleteActive() throws {
        let store = InMemoryLayoutStore()
        let (documents, activeID) = try store.loadOrSeed(now: referenceDate)

        try store.delete(activeID)

        let remaining = try store.loadAll()
        #expect(remaining.count == documents.count - 1)
        let next = try #require(store.loadActiveID())
        #expect(next != activeID)
    }
}
