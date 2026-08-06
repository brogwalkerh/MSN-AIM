import SwiftUI
import CarDashCore

/// The dashboard: the tiled canvas plus the few controls that sit on top of it.
public struct DashboardView: View {
    /// Owned by `RootView` via `@State`; observed here, not owned.
    private let model: LayoutModel
    @State private var showingLibrary = false

    @Environment(\.dashTheme) private var theme

    public init(model: LayoutModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.background.ignoresSafeArea()

            TilingCanvas(model: model) { pane in
                PanePlaceholderView(pane: pane)
            }
            .padding(LayoutMetrics.gutter)

            controls
                .padding(.top, 8)
                .padding(.trailing, 12)

            overflowRail
            refusalBanner
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingLibrary) {
            LayoutLibrarySheet(model: model)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            if model.isEditing, model.isShowingDerivedLayout {
                Button("Reset portrait") {
                    model.resetPortraitVariant()
                }
                .font(DashFont.label())
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(theme.tile, in: Capsule())
            }

            circularButton(
                systemImage: "square.grid.2x2",
                label: "Layouts",
                isOn: showingLibrary
            ) {
                showingLibrary = true
            }

            circularButton(
                systemImage: model.isEditing ? "checkmark" : "slider.horizontal.3",
                label: model.isEditing ? "Done rearranging" : "Rearrange tiles",
                isOn: model.isEditing
            ) {
                withAnimation(.snappy(duration: 0.25)) {
                    model.isEditing.toggle()
                }
                Haptics.edit()
            }
        }
    }

    private func circularButton(
        systemImage: String,
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? theme.background : theme.primaryText)
                .frame(width: DashMetrics.minimumHitTarget, height: DashMetrics.minimumHitTarget)
                .background(isOn ? theme.accent : theme.tile, in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Overflow

    /// In portrait there is not room for every tile, so the ones that were demoted are
    /// offered here rather than silently dropped. Tapping one swaps it into the largest
    /// tile on screen — which promotes the derived portrait layout to an authored one,
    /// so the choice sticks.
    @ViewBuilder
    private var overflowRail: some View {
        let rendered = model.rendered(for: model.canvasSize)
        if !rendered.adapted.overflow.isEmpty {
            VStack {
                Spacer()
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(rendered.adapted.overflow) { pane in
                            Button {
                                swapIn(pane.sectionID, using: rendered)
                            } label: {
                                Label(
                                    SectionCatalog.title(for: pane.sectionID),
                                    systemImage: SectionCatalog.systemImage(for: pane.sectionID)
                                )
                                .font(DashFont.label())
                                .foregroundStyle(theme.primaryText)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(theme.tile, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                .frame(height: 60)
                .padding(.bottom, 6)
            }
        }
    }

    private func swapIn(_ sectionID: SectionID, using rendered: LayoutModel.RenderedLayout) {
        let largest = rendered.solution.panes.max { lhs, rhs in
            (rendered.solution.rect(for: lhs.id)?.area ?? 0)
                < (rendered.solution.rect(for: rhs.id)?.area ?? 0)
        }
        guard let largest else { return }
        model.replace(largest.id, with: sectionID)
        Haptics.edit()
    }

    // MARK: - Refusals

    /// Refused edits — a split with nowhere to go, the last layout being deleted — are
    /// normal things to attempt, so they get an explanation rather than a silent no-op.
    @ViewBuilder
    private var refusalBanner: some View {
        if let refusal = model.lastRefusal {
            VStack {
                Text(refusal)
                    .font(DashFont.label())
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.tile, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.destructive.opacity(0.5)))
                    .padding(.top, 14)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: refusal) {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { model.lastRefusal = nil }
            }
        }
    }
}
