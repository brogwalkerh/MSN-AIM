import SwiftUI
import CarDashCore

/// Draws a layout: every tile at its solved frame, with a draggable divider between
/// each pair.
///
/// The view does no layout arithmetic of its own. It asks `LayoutModel` for a solved
/// arrangement at the size it has been given and places rectangles — which is why the
/// interesting behaviour can be tested on Linux without a screen.
public struct TilingCanvas<PaneContent: View>: View {
    private let model: LayoutModel
    private let paneContent: (Pane) -> PaneContent

    @Environment(\.dashTheme) private var theme

    public init(
        model: LayoutModel,
        @ViewBuilder paneContent: @escaping (Pane) -> PaneContent
    ) {
        self.model = model
        self.paneContent = paneContent
    }

    public var body: some View {
        GeometryReader { proxy in
            // Solved from the size this pass actually has, not from the model's stored
            // canvas size. Reading the stored value would render one frame of the
            // previous arrangement at launch and on every rotation.
            let rendered = model.rendered(for: LayoutSize(proxy.size))

            ZStack(alignment: .topLeading) {
                ForEach(rendered.solution.panes) { pane in
                    tile(pane, in: rendered)
                }

                ForEach(rendered.solution.dividers) { divider in
                    DividerHandle(
                        divider: divider,
                        isEditing: model.isEditing,
                        onChange: { model.setFraction(divider.id, to: $0) },
                        onEnd: { model.commitDrag() }
                    )
                }
            }
            // Tiles appearing, disappearing or trading places is worth animating.
            // Divider drags are not — the value below deliberately does not change
            // during a resize, so the tiles track the finger with no interpolation.
            .animation(.snappy(duration: 0.28), value: rendered.solution.panes)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                model.setCanvasSize(LayoutSize(size))
            }
        }
    }

    @ViewBuilder
    private func tile(_ pane: Pane, in rendered: LayoutModel.RenderedLayout) -> some View {
        if let rect = rendered.solution.rect(for: pane.id) {
            PaneChrome(
                pane: pane,
                isEditing: model.isEditing,
                canSplit: model.canAddPane,
                canRemove: rendered.solution.panes.count > 1,
                onSplit: { model.split(pane.id, axis: $0, inserting: suggestedSection(for: rendered)) },
                onReplace: { model.replace(pane.id, with: $0) },
                onRemove: { model.remove(pane.id) },
                content: { paneContent(pane) }
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.center.x, y: rect.center.y)
        }
    }

    /// What to drop into a newly created tile.
    ///
    /// Picking the first section not already on screen beats always inserting the same
    /// one: splitting a tile usually means "I want something else here too", and this
    /// gets it right often enough to save a trip through the replace menu.
    private func suggestedSection(for rendered: LayoutModel.RenderedLayout) -> SectionID {
        let inUse = Set(rendered.adapted.tree.sectionIDs)
        return SectionCatalog.entries.first { !inUse.contains($0.id) }?.id ?? .clock
    }
}
