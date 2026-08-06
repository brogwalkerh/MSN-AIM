import Foundation

/// The per-canvas trees belonging to one saved layout.
///
/// Deliberately a struct with named fields rather than `[CanvasClass: LayoutTree]`. Two
/// reasons: it puts "landscape is the canonical one, the others are optional" into the
/// type rather than a comment, and a dictionary keyed by an enum encodes as a flat
/// alternating array in JSON unless extra conformances are bolted on — which would make
/// the golden fixtures unreadable and migrations harder than they need to be.
public struct LayoutVariants: Hashable, Sendable, Codable {
    /// Always present. The layout the user arranges.
    public var phoneLandscape: LayoutTree
    /// Authored portrait layout. Nil means "derive one" — see `LayoutTree.adapted(to:)`.
    public var phonePortrait: LayoutTree?
    /// Nil means "use the landscape tree", which is usually right: the tree is
    /// fraction-based, so it scales to a larger canvas without changing.
    public var tabletWide: LayoutTree?

    public init(
        phoneLandscape: LayoutTree,
        phonePortrait: LayoutTree? = nil,
        tabletWide: LayoutTree? = nil
    ) {
        self.phoneLandscape = phoneLandscape
        self.phonePortrait = phonePortrait
        self.tabletWide = tabletWide
    }

    /// The authored tree for a canvas class, if there is one.
    public subscript(canvasClass: CanvasClass) -> LayoutTree? {
        get {
            switch canvasClass {
            case .phoneLandscape: return phoneLandscape
            case .phonePortrait: return phonePortrait
            case .tabletWide: return tabletWide
            }
        }
        set {
            switch canvasClass {
            case .phoneLandscape:
                if let newValue { phoneLandscape = newValue }
            case .phonePortrait:
                phonePortrait = newValue
            case .tabletWide:
                tabletWide = newValue
            }
        }
    }
}

/// One saved dashboard arrangement.
public struct LayoutDocument: Hashable, Sendable, Codable, Identifiable {
    /// Bumped when the on-disk shape changes. `LayoutMigrator` dispatches on it.
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var variants: LayoutVariants
    public var createdAt: Date
    public var modifiedAt: Date

    /// The version this build writes.
    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = LayoutDocument.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        variants: LayoutVariants,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.variants = variants
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public init(name: String, tree: LayoutTree, now: Date) {
        self.init(
            name: name,
            variants: LayoutVariants(phoneLandscape: tree),
            createdAt: now,
            modifiedAt: now
        )
    }

    /// The tree to draw on a given canvas, deriving one where none was authored.
    ///
    /// - Returns: the tree plus any tiles that had to be demoted to fit. Callers show
    ///   the demoted sections in a switcher rail rather than dropping them silently.
    public func layout(
        for canvasClass: CanvasClass,
        canvas: LayoutSize,
        policy: MinimumSizePolicy = .uniform,
        gutter: Double = LayoutMetrics.gutter
    ) -> AdaptedLayout {
        if let authored = variants[canvasClass] {
            return AdaptedLayout(tree: authored, overflow: [])
        }
        return variants.phoneLandscape.adapted(
            to: canvasClass,
            canvas: canvas,
            policy: policy,
            gutter: gutter
        )
    }
}
