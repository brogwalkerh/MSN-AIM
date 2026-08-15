import Foundation

/// Reading and writing `.cardash` files.
///
/// Exporting a layout is easy. Importing one is where the care goes, because an imported file
/// is the only input this app takes that it did not write itself — it arrived through AirDrop,
/// Messages or a download, and it may be truncated, from a newer build, hand-edited, or simply
/// not a layout at all. None of those may crash the app or produce a dashboard that cannot be
/// used, and "it opened but every tile is 2 points wide" counts as the latter.
///
/// The whole of it is pure, so every one of those cases is a test rather than a hope.
public enum LayoutTransfer {
    /// The file extension and the UTI the app exports.
    public static let fileExtension = "cardash"
    public static let contentType = "com.brogwalkerh.cardash.layout"

    /// Bumped only if the envelope shape changes, which is separate from the document's own
    /// `schemaVersion` — a newer app could keep this envelope and change the layout format, or
    /// the reverse.
    public static let currentFormatVersion = 1

    /// What a `.cardash` file contains.
    ///
    /// An envelope rather than the bare document, so a file can be recognised as a CarDash
    /// layout before being decoded. Without the marker, deciding whether an arbitrary JSON file
    /// is a layout means attempting a full decode and treating failure as "not ours", which
    /// cannot distinguish "not a layout" from "a layout this build cannot read" — and those
    /// deserve different messages.
    public struct Envelope: Codable, Hashable, Sendable {
        public var format: String
        public var formatVersion: Int
        public var exportedAt: Date
        public var document: LayoutDocument

        /// Identifies the file as ours regardless of extension or how it was transferred.
        public static let marker = "cardash.layout"

        public init(document: LayoutDocument, exportedAt: Date) {
            self.format = Self.marker
            self.formatVersion = LayoutTransfer.currentFormatVersion
            self.exportedAt = exportedAt
            self.document = document
        }
    }

    // MARK: - Export

    public static func export(_ document: LayoutDocument, now: Date) throws -> Data {
        try LayoutCodec.makeEncoder().encode(Envelope(document: document, exportedAt: now))
    }

    /// A filename safe on any filesystem, derived from the layout's name.
    ///
    /// Slashes and colons are the ones that matter — a layout called "Home/Work" would otherwise
    /// produce a path, not a name.
    public static func filename(for document: LayoutDocument) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = document.name.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { partial, character in
                // Collapse runs, so "Home / Work" does not become "Home---Work".
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))

        let base = cleaned.isEmpty ? "layout" : String(cleaned.prefix(40))
        return "\(base).\(fileExtension)"
    }

    // MARK: - Import

    public enum ImportError: Error, Hashable, Sendable {
        case notALayoutFile
        case fromANewerVersion(found: Int, supported: Int)
        case unreadable(String)
        case tooLarge(bytes: Int)

        public var userFacingMessage: String {
            switch self {
            case .notALayoutFile:
                return "That file isn't a CarDash layout."
            case .fromANewerVersion:
                return "That layout was made with a newer version of CarDash."
            case .unreadable:
                return "That layout file is damaged and couldn't be read."
            case .tooLarge:
                return "That file is too large to be a layout."
            }
        }
    }

    /// A ceiling on file size, checked before parsing.
    ///
    /// A real layout is a couple of kilobytes — the largest a phone can hold is six tiles. The
    /// cap is far above that and still far below anything that would make the JSON parser work
    /// hard, and refusing early costs nothing.
    public static let maximumFileSize = 256_000

    /// How deeply nested a layout may be before it is refused.
    ///
    /// The editor's own ceiling is 4 (`SplitLimits.tablet`), so this is generous. It exists for
    /// a hand-written file rather than a real one: `LayoutNode` is recursive, and every walk
    /// over it — including the decoder's own — recurses with it, so a deliberately deep file is
    /// a way to exhaust the stack rather than a way to make an interesting dashboard.
    public static let maximumDepth = 16

    /// Reads a `.cardash` file into a document ready to be added to the library.
    ///
    /// Named `restore` rather than `import`, which is a statement keyword — `LayoutTransfer
    /// .import(...)` parses, but only just, and reads worse than it should.
    ///
    /// - Parameters:
    ///   - existingNames: names already in the library, so the import can be disambiguated.
    ///   - now: the imported document's creation date.
    /// - Returns: a document with a **fresh identity**. Importing must never overwrite an
    ///   existing layout, and re-importing your own export is a normal thing to do — keeping
    ///   the original id would silently replace the layout you exported from.
    public static func restore(
        _ data: Data,
        existingNames: [String] = [],
        now: Date
    ) throws -> LayoutDocument {
        guard data.count <= maximumFileSize else {
            throw ImportError.tooLarge(bytes: data.count)
        }

        let envelope: Envelope
        do {
            envelope = try LayoutCodec.makeDecoder().decode(Envelope.self, from: data)
        } catch {
            // Distinguish "not ours" from "ours but damaged" by looking for the marker, so the
            // message can be about the right thing.
            if looksLikeALayoutFile(data) {
                throw ImportError.unreadable("\(error)")
            }
            throw ImportError.notALayoutFile
        }

        guard envelope.format == Envelope.marker else {
            throw ImportError.notALayoutFile
        }
        guard envelope.formatVersion <= currentFormatVersion else {
            throw ImportError.fromANewerVersion(
                found: envelope.formatVersion,
                supported: currentFormatVersion
            )
        }

        for tree in [
            envelope.document.variants.phoneLandscape,
            envelope.document.variants.phonePortrait,
            envelope.document.variants.tabletWide
        ].compactMap({ $0 }) where depth(of: tree.root) > maximumDepth {
            throw ImportError.unreadable("layout nested more than \(maximumDepth) deep")
        }

        var document = envelope.document
        document.id = UUID()
        document.createdAt = now
        document.modifiedAt = now
        document.name = uniqueName(document.name, among: existingNames)
        document.variants = sanitised(document.variants)
        return document
    }

    /// Cheap check for the marker without a full parse.
    static func looksLikeALayoutFile(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(4096), encoding: .utf8) else { return false }
        return text.contains(Envelope.marker)
    }

    // MARK: - Making an imported layout usable

    /// Ensures the name does not collide, in the way a file manager does.
    ///
    /// Re-importing the same file repeatedly is normal — it is how someone tries a shared
    /// layout, tweaks it, and tries again — and three entries called "Driving" would be
    /// indistinguishable in the library.
    public static func uniqueName(_ desired: String, among existing: [String]) -> String {
        let trimmed = desired.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Imported layout" : String(trimmed.prefix(60))
        guard existing.contains(base) else { return base }

        // Bounded rather than `while true`: a library that somehow contains 999 layouts called
        // "Driving" should still import rather than spin.
        for suffix in 2...999 {
            let candidate = "\(base) \(suffix)"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    /// Nesting depth, counted without recursion.
    ///
    /// Iterative on purpose: the point of the check is to refuse a file deep enough to exhaust
    /// the stack, and a recursive depth check would fall over on exactly the input it exists to
    /// reject.
    static func depth(of root: LayoutNode) -> Int {
        var deepest = 0
        var stack: [(node: LayoutNode, depth: Int)] = [(root, 1)]

        while let (node, depth) = stack.popLast() {
            deepest = max(deepest, depth)
            // No point walking a pathological file to the end once it has already failed.
            if deepest > maximumDepth { return deepest }
            if case .split(let split) = node {
                stack.append((split.first, depth + 1))
                stack.append((split.second, depth + 1))
            }
        }
        return deepest
    }

    /// Clamps anything a hand-edited or newer file might contain that would render badly.
    ///
    /// Unknown `SectionID`s are deliberately *not* removed: the app already draws a "this
    /// version doesn't have that tile" placeholder with a replace button, and dropping the tile
    /// instead would silently change a shared layout's shape.
    ///
    /// Fractions are a different matter. `Split.init` clamps them, but `Codable` decodes
    /// straight into the stored property and never calls it — so a hand-edited file can carry a
    /// fraction of 0.999, or a NaN, that the engine itself could never have produced.
    static func sanitised(_ variants: LayoutVariants) -> LayoutVariants {
        LayoutVariants(
            phoneLandscape: sanitised(variants.phoneLandscape),
            phonePortrait: variants.phonePortrait.map(sanitised),
            tabletWide: variants.tabletWide.map(sanitised)
        )
    }

    static func sanitised(_ tree: LayoutTree) -> LayoutTree {
        LayoutTree(root: sanitised(tree.root))
    }

    private static func sanitised(_ node: LayoutNode) -> LayoutNode {
        switch node {
        case .pane:
            return node
        case .split(let split):
            var clean = split
            // The engine's own clamp, not a tighter one: re-importing your own export has to be
            // lossless, and the app can legitimately produce a fraction as extreme as 0.01.
            clean.fraction = Split.clampToOpenUnitInterval(split.fraction)
            clean.first = sanitised(split.first)
            clean.second = sanitised(split.second)
            return .split(clean)
        }
    }
}
