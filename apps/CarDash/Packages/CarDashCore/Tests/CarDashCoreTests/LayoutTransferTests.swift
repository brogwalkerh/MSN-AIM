import Foundation
import Testing
@testable import CarDashCore

@Suite("Layout export")
struct LayoutExportTests {
    private let now = Date(timeIntervalSince1970: 1_754_463_600)

    private func document(named name: String = "Driving") -> LayoutDocument {
        LayoutDocument(name: name, tree: LayoutPresets.quad, now: now)
    }

    @Test("An exported file carries the marker that identifies it as ours")
    func marker() throws {
        let data = try LayoutTransfer.export(document(), now: now)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(LayoutTransfer.Envelope.marker))
        #expect(LayoutTransfer.looksLikeALayoutFile(data))
    }

    @Test("Export then import is lossless in everything but identity")
    func roundTrip() throws {
        let original = document()
        let restored = try LayoutTransfer.restore(
            try LayoutTransfer.export(original, now: now),
            now: now
        )

        #expect(restored.variants == original.variants, "the arrangement itself must survive")
        #expect(restored.name == original.name)
        #expect(restored.schemaVersion == original.schemaVersion)
    }

    // Re-importing your own export is a normal thing to do — it is how someone tries a shared
    // layout, edits it, and tries again. Keeping the id would silently overwrite the layout
    // that was exported from.
    @Test("Importing never reuses the original identity")
    func freshIdentity() throws {
        let original = document()
        let data = try LayoutTransfer.export(original, now: now)

        let first = try LayoutTransfer.restore(data, now: now)
        let second = try LayoutTransfer.restore(data, now: now)

        #expect(first.id != original.id)
        #expect(second.id != first.id)
    }

    // A fraction as extreme as 0.01 is something the app itself can produce, so clamping
    // imports any tighter would quietly rearrange a layout on the way back in.
    @Test("An extreme but legitimate fraction survives the round trip")
    func extremeFractionSurvives() throws {
        var tree = LayoutTree(.map)
        let paneID = tree.panes[0].id
        _ = try tree.split(paneID, axis: .horizontal, inserting: .clock)
        // After one split the root *is* the divider — the split and the divider are the same
        // object in this engine.
        let dividerID = try #require(tree.root.asSplit?.id)
        try tree.setFraction(dividerID, to: 0.02)

        let source = LayoutDocument(name: "Lopsided", tree: tree, now: now)
        let restored = try LayoutTransfer.restore(
            try LayoutTransfer.export(source, now: now),
            now: now
        )
        let fraction = try #require(restored.variants.phoneLandscape.root.asSplit?.fraction)
        #expect(abs(fraction - 0.02) < 1e-9)
    }

    @Test(
        "Filenames are safe on any filesystem",
        arguments: [
            ("Driving", "Driving.cardash"),
            ("Home/Work", "Home-Work.cardash"),
            ("Home / Work", "Home-Work.cardash"),
            ("", "layout.cardash"),
            ("///", "layout.cardash"),
            ("Café ☕️", "Caf-.cardash")
        ]
    )
    func filenames(name: String, expected: String) {
        #expect(LayoutTransfer.filename(for: document(named: name)) == expected)
    }

    @Test("A very long name does not produce a very long filename")
    func longFilename() {
        let name = String(repeating: "a", count: 300)
        let filename = LayoutTransfer.filename(for: document(named: name))
        #expect(filename.count < 60)
        #expect(filename.hasSuffix(".cardash"))
    }
}

// An imported file is the only input this app takes that it did not write itself. It arrived
// by AirDrop or download, and it may be truncated, hand-edited, from a newer build, or not a
// layout at all. None of that may crash, and none of it may produce a dashboard that cannot
// be used.
@Suite("Layout import, hostile inputs")
struct LayoutImportTests {
    private let now = Date(timeIntervalSince1970: 1_754_463_600)

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    @Test(
        "Files that are not layouts are refused as such",
        arguments: ["", "{}", "[]", "not json at all", #"{"hello":"world"}"#]
    )
    func notALayout(raw: String) {
        #expect(throws: LayoutTransfer.ImportError.notALayoutFile) {
            try LayoutTransfer.restore(bytes(raw), now: now)
        }
    }

    // "Not a layout" and "a layout I can't read" deserve different messages, so the marker is
    // checked separately from whether the decode succeeded.
    @Test("A damaged layout is reported as damaged, not as the wrong kind of file")
    func damagedLayout() throws {
        let good = try LayoutTransfer.export(
            LayoutDocument(name: "Driving", tree: LayoutPresets.quad, now: now),
            now: now
        )
        let truncated = good.prefix(good.count / 2)

        let error = #expect(throws: LayoutTransfer.ImportError.self) {
            try LayoutTransfer.restore(Data(truncated), now: now)
        }
        guard case .unreadable = try #require(error) else {
            Issue.record("expected .unreadable, got \(String(describing: error))")
            return
        }
    }

    @Test("A file from a newer version says so rather than failing obscurely")
    func newerVersion() throws {
        var envelope = LayoutTransfer.Envelope(
            document: LayoutDocument(name: "Future", tree: LayoutPresets.quad, now: now),
            exportedAt: now
        )
        envelope.formatVersion = LayoutTransfer.currentFormatVersion + 1
        let data = try LayoutCodec.makeEncoder().encode(envelope)

        let error = #expect(throws: LayoutTransfer.ImportError.self) {
            try LayoutTransfer.restore(data, now: now)
        }
        #expect(
            error == .fromANewerVersion(
                found: LayoutTransfer.currentFormatVersion + 1,
                supported: LayoutTransfer.currentFormatVersion
            )
        )
    }

    @Test("Oversized files are refused before being parsed")
    func tooLarge() {
        let huge = Data(repeating: 0x7B, count: LayoutTransfer.maximumFileSize + 1)
        let error = #expect(throws: LayoutTransfer.ImportError.self) {
            try LayoutTransfer.restore(huge, now: now)
        }
        #expect(error == .tooLarge(bytes: LayoutTransfer.maximumFileSize + 1))
    }

    // LayoutNode is recursive, and every walk over it recurses — including the decoder's. A
    // deliberately deep file is a way to exhaust the stack, not a way to make an interesting
    // dashboard.
    @Test("A pathologically nested layout is refused")
    func tooDeep() throws {
        var node = LayoutNode.pane(.clock)
        for _ in 0..<(LayoutTransfer.maximumDepth + 4) {
            node = .split(.horizontal, 0.5, node, .pane(.map))
        }
        let document = LayoutDocument(
            name: "Deep",
            variants: LayoutVariants(phoneLandscape: LayoutTree(root: node)),
            createdAt: now,
            modifiedAt: now
        )
        let data = try LayoutTransfer.export(document, now: now)

        #expect(throws: LayoutTransfer.ImportError.self) {
            try LayoutTransfer.restore(data, now: now)
        }
    }

    @Test("Depth is measured without recursing, so the check survives its own worst case")
    func depthIsIterative() {
        var node = LayoutNode.pane(.clock)
        for _ in 0..<5_000 {
            node = .split(.vertical, 0.5, node, .pane(.map))
        }
        // Would overflow the stack if this walked recursively.
        #expect(LayoutTransfer.depth(of: node) > LayoutTransfer.maximumDepth)
    }

    // Split.init clamps fractions, but Codable decodes straight into the stored property and
    // never calls it — so these values genuinely reach the engine from a hand-edited file.
    @Test(
        "Fractions outside the legal range are clamped on the way in",
        arguments: [1.5, -0.5, 0.0, 1.0, Double.infinity, Double.nan]
    )
    func illegalFractions(fraction: Double) throws {
        let split = Split(axis: .horizontal, fraction: 0.5, first: .pane(.map), second: .pane(.clock))
        var broken = split
        broken.fraction = fraction   // bypasses the initialiser, exactly as decoding does

        let sanitised = LayoutTransfer.sanitised(LayoutTree(root: .split(broken)))
        let result = try #require(sanitised.root.asSplit?.fraction)

        #expect(result.isFinite)
        #expect(result > 0 && result < 1, "a tile with zero extent cannot be seen or dragged back")
    }

    // The app already draws a "this version doesn't have that tile" placeholder with a replace
    // button. Silently dropping the tile instead would change a shared layout's shape.
    @Test("An unknown section is kept rather than stripped")
    func unknownSectionSurvives() throws {
        let document = LayoutDocument(
            name: "From the future",
            tree: LayoutTree(root: .split(.horizontal, 0.5, .pane(.map), .pane(SectionID("tirePressure")))),
            now: now
        )
        let restored = try LayoutTransfer.restore(
            try LayoutTransfer.export(document, now: now),
            now: now
        )
        #expect(restored.variants.phoneLandscape.sectionIDs.contains(SectionID("tirePressure")))
    }

    @Test("Names are disambiguated the way a file manager does")
    func uniqueNames() {
        #expect(LayoutTransfer.uniqueName("Driving", among: []) == "Driving")
        #expect(LayoutTransfer.uniqueName("Driving", among: ["Driving"]) == "Driving 2")
        #expect(LayoutTransfer.uniqueName("Driving", among: ["Driving", "Driving 2"]) == "Driving 3")
        #expect(LayoutTransfer.uniqueName("Other", among: ["Driving"]) == "Other")
        #expect(LayoutTransfer.uniqueName("  ", among: []) == "Imported layout")
        #expect(LayoutTransfer.uniqueName("  Driving  ", among: []) == "Driving")
    }

    @Test("Importing twice gives two distinguishable entries")
    func repeatedImportsAreDistinguishable() throws {
        let data = try LayoutTransfer.export(
            LayoutDocument(name: "Driving", tree: LayoutPresets.quad, now: now),
            now: now
        )
        let first = try LayoutTransfer.restore(data, existingNames: [], now: now)
        let second = try LayoutTransfer.restore(data, existingNames: [first.name], now: now)

        #expect(first.name == "Driving")
        #expect(second.name == "Driving 2")
    }

    @Test("An absurdly long name is truncated rather than carried into the library")
    func longName() throws {
        let document = LayoutDocument(
            name: String(repeating: "z", count: 500),
            tree: LayoutPresets.quad,
            now: now
        )
        let restored = try LayoutTransfer.restore(
            try LayoutTransfer.export(document, now: now),
            now: now
        )
        #expect(restored.name.count <= 60)
    }

    @Test("Every import error has something a person could act on")
    func messages() {
        let cases: [LayoutTransfer.ImportError] = [
            .notALayoutFile,
            .fromANewerVersion(found: 2, supported: 1),
            .unreadable("EOF"),
            .tooLarge(bytes: 999)
        ]
        for error in cases {
            #expect(!error.userFacingMessage.isEmpty)
            #expect(!error.userFacingMessage.contains("EOF"), "no parser diagnostics in the UI")
        }
    }
}
