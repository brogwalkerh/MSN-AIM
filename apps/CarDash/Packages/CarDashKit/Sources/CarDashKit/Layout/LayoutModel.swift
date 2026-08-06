import Foundation
import Observation
import CarDashCore
import os

/// The app's live dashboard state: which layouts exist, which one is showing, how big
/// the screen is, and whether the user is rearranging.
///
/// All the interesting logic lives in `CarDashCore` — this is the imperative shell that
/// holds a document, applies edits to the right variant, and persists the result.
@MainActor
@Observable
public final class LayoutModel {
    public private(set) var documents: [LayoutDocument] = []
    public private(set) var activeID: UUID

    /// Set by the canvas as the screen reports its size. Drives which variant is drawn.
    public private(set) var canvasSize: LayoutSize = ReferenceCanvas.phone

    public var isEditing = false

    /// The last refused edit, for the UI to surface. Refusals are normal — splitting a
    /// tile that has no room is a legitimate thing to try — so they are reported rather
    /// than thrown at the caller.
    public var lastRefusal: String?

    @ObservationIgnored private let store: any LayoutStore
    @ObservationIgnored private let policy: MinimumSizePolicy
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "layout")

    public init(
        store: any LayoutStore,
        policy: MinimumSizePolicy = SectionMetrics.builtInPolicy,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.policy = policy
        self.clock = clock

        do {
            let (documents, activeID) = try store.loadOrSeed(now: clock())
            self.documents = documents
            self.activeID = activeID
        } catch {
            // Losing the saved library is bad; refusing to launch is worse. Come up on
            // the presets and let the user rebuild.
            Self.log.error("could not load layouts, falling back to presets: \(error)")
            let seeded = LayoutPresets.all.map { $0.document(now: clock()) }
            self.documents = seeded
            self.activeID = seeded[0].id
        }
    }

    // MARK: - Derived state

    public var activeDocument: LayoutDocument {
        documents.first { $0.id == activeID }
            ?? documents.first
            ?? LayoutPresets.default.document(now: clock())
    }

    public var canvasClass: CanvasClass {
        CanvasClass.classify(canvasSize)
    }

    public var splitLimits: SplitLimits {
        canvasClass.splitLimits
    }

    /// The tree actually being drawn, plus anything demoted to the overflow rail.
    public var displayed: AdaptedLayout {
        activeDocument.layout(for: canvasClass, canvas: canvasSize, policy: policy)
    }

    public var solution: LayoutSolution {
        rendered(for: canvasSize).solution
    }

    /// Everything needed to draw the dashboard at a given size.
    ///
    /// Takes the size as a parameter rather than reading `canvasSize` so the view can
    /// render correctly on its very first layout pass, before `setCanvasSize` has been
    /// called — otherwise the app shows one frame of the wrong arrangement at launch and
    /// on every rotation.
    public struct RenderedLayout {
        public let canvasSize: LayoutSize
        public let canvasClass: CanvasClass
        public let adapted: AdaptedLayout
        public let solution: LayoutSolution
    }

    public func rendered(for size: LayoutSize) -> RenderedLayout {
        let size = size.isEmpty ? ReferenceCanvas.phone : size
        let canvasClass = CanvasClass.classify(size)
        let adapted = activeDocument.layout(for: canvasClass, canvas: size, policy: policy)
        return RenderedLayout(
            canvasSize: size,
            canvasClass: canvasClass,
            adapted: adapted,
            solution: LayoutSolver.solve(
                adapted.tree,
                in: LayoutRect(origin: .zero, size: size),
                policy: policy
            )
        )
    }

    /// True when the arrangement on screen was derived rather than authored, which the
    /// editor surfaces so it is clear why portrait looks different.
    public var isShowingDerivedLayout: Bool {
        displayed.isDerived
    }

    public var canAddPane: Bool {
        displayed.tree.paneCount < splitLimits.maxPanes
    }

    public func setCanvasSize(_ size: LayoutSize) {
        guard size != canvasSize, !size.isEmpty else { return }
        canvasSize = size
    }

    // MARK: - Editing

    public func split(_ paneID: PaneID, axis: SplitAxis, inserting sectionID: SectionID) {
        edit { tree in
            try tree.split(
                paneID,
                axis: axis,
                inserting: sectionID,
                fitting: canvasSize,
                policy: policy,
                limits: splitLimits
            )
        }
    }

    public func remove(_ paneID: PaneID) {
        edit { try $0.remove(paneID) }
    }

    public func replace(_ paneID: PaneID, with sectionID: SectionID) {
        edit { try $0.replace(paneID, with: sectionID) }
    }

    public func exchange(_ a: PaneID, _ b: PaneID) {
        edit { try $0.exchange(a, b) }
    }

    public func setState(_ state: SectionState, for paneID: PaneID) {
        edit { try $0.setState(state, for: paneID) }
    }

    /// Called continuously while a divider is dragged, so it deliberately does not
    /// write to disk — a file per frame would be absurd. `commitDrag()` saves once the
    /// gesture ends.
    public func setFraction(_ dividerID: DividerID, to fraction: Double) {
        edit(persist: false) { try $0.setFraction(dividerID, to: fraction) }
    }

    public func commitDrag() {
        persistActiveDocument()
    }

    // MARK: - Library

    public func selectDocument(_ id: UUID) {
        guard documents.contains(where: { $0.id == id }) else { return }
        activeID = id
        store.setActiveID(id)
    }

    @discardableResult
    public func addDocument(from preset: LayoutPresets.Preset) -> UUID {
        let document = preset.document(now: clock())
        documents.append(document)
        try? store.save(document)
        selectDocument(document.id)
        return document.id
    }

    public func deleteDocument(_ id: UUID) {
        // The library is the only way back to a working dashboard, so it never empties.
        guard documents.count > 1 else {
            lastRefusal = "This is your last layout."
            return
        }
        documents.removeAll { $0.id == id }
        try? store.delete(id)
        if activeID == id, let next = documents.first {
            selectDocument(next.id)
        }
    }

    public func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }
        documents[index].name = trimmed
        documents[index].modifiedAt = clock()
        try? store.save(documents[index])
    }

    /// Drops any derived-then-authored portrait variant, so portrait goes back to
    /// tracking the landscape layout.
    public func resetPortraitVariant() {
        guard let index = documents.firstIndex(where: { $0.id == activeID }) else { return }
        documents[index].variants.phonePortrait = nil
        documents[index].modifiedAt = clock()
        try? store.save(documents[index])
    }

    // MARK: - Plumbing

    /// Applies an edit to whichever variant is currently on screen, then saves.
    private func edit(persist: Bool = true, _ body: (inout LayoutTree) throws -> Void) {
        guard let index = documents.firstIndex(where: { $0.id == activeID }) else { return }

        var tree = editableTree(of: documents[index])
        do {
            try body(&tree)
        } catch {
            lastRefusal = (error as? LayoutError).map { String(describing: $0) }
                ?? "That change could not be applied."
            Self.log.debug("edit refused: \(error)")
            return
        }

        lastRefusal = nil
        apply(tree, to: &documents[index])
        documents[index].modifiedAt = clock()

        if persist {
            persistActiveDocument()
        }
    }

    /// The tree an edit should modify for the current canvas.
    ///
    /// Portrait is the interesting case. It is normally derived from the landscape
    /// layout, so rearranging it would be undone the moment it was recomputed. The first
    /// portrait edit therefore promotes what is on screen to an authored variant, and it
    /// sticks from then on. `resetPortraitVariant()` undoes that.
    private func editableTree(of document: LayoutDocument) -> LayoutTree {
        switch canvasClass {
        case .phoneLandscape:
            return document.variants.phoneLandscape
        case .tabletWide:
            return document.variants.tabletWide ?? document.variants.phoneLandscape
        case .phonePortrait:
            return document.variants.phonePortrait ?? displayed.tree
        }
    }

    private func apply(_ tree: LayoutTree, to document: inout LayoutDocument) {
        switch canvasClass {
        case .phoneLandscape:
            document.variants.phoneLandscape = tree
        case .tabletWide:
            // Only start keeping a separate tablet variant once one has been edited
            // there; until then the canonical tree simply scales.
            if document.variants.tabletWide == nil {
                document.variants.phoneLandscape = tree
            } else {
                document.variants.tabletWide = tree
            }
        case .phonePortrait:
            document.variants.phonePortrait = tree
        }
    }

    private func persistActiveDocument() {
        guard let document = documents.first(where: { $0.id == activeID }) else { return }
        do {
            try store.save(document)
        } catch {
            Self.log.error("could not save layout: \(error)")
        }
    }
}
