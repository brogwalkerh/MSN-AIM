import SwiftUI
import CarDashCore

/// The dashboard: the tiled canvas plus the few controls that sit on top of it.
public struct DashboardView: View {
    /// Owned by `RootView` via `@State`; observed here, not owned.
    private let model: LayoutModel
    private let services: AppServices

    @State private var showingLibrary = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    public init(model: LayoutModel, services: AppServices) {
        self.model = model
        self.services = services
    }

    private var theme: DashTheme { services.theme.theme }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.background.ignoresSafeArea()

            TilingCanvas(model: model, services: services)
                .padding(services.density.canvasInset)

            controls
                .padding(.top, 8)
                .padding(.trailing, 12)

            overflowRail
            refusalBanner
        }
        .environment(\.dashTheme, theme)
        .environment(\.dashDensity, services.density)
        .preferredColorScheme(services.theme.isNight ? .dark : .light)
        .sheet(isPresented: $showingLibrary) {
            LayoutLibrarySheet(model: model, registry: services.registry)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(services: services)
        }
        .task {
            services.start()
            // The solver needs the gutter, and it lives on the model rather than in the
            // environment because it is an input to the layout arithmetic, not to drawing.
            model.density = services.density
        }
        .onChange(of: services.density) { _, density in
            withAnimation(.snappy(duration: 0.25)) { model.density = density }
        }
        .onChange(of: services.location.coordinate) { _, coordinate in
            services.positionChanged(to: coordinate)
        }
        .onChange(of: scenePhase) { _, phase in
            // The sun moves while the app is backgrounded, and a drive can easily span
            // sunset. Re-evaluating on return is cheaper than a running timer.
            if phase == .active { services.theme.refresh() }
        }
        // Rearranging tiles while moving is the one interaction that has no business
        // happening at speed, so it is not merely discouraged — it is switched off.
        .onChange(of: services.location.isDriving) { _, isDriving in
            if isDriving, model.isEditing {
                withAnimation(.snappy) { model.isEditing = false }
            }
        }
    }

    // MARK: - Controls

    /// The floating controls, top right.
    ///
    /// They sit over the canvas rather than in a bar of their own, because a permanent bar on a
    /// landscape phone costs a strip of screen that the tiles need more. The consequence is that
    /// they are always on top of *something* — usually the map — so they carry their own
    /// background rather than relying on the tile behind them for contrast. Bare circles at
    /// `theme.tile` (white at 6%) over a bright map are all but invisible.
    private var controls: some View {
        HStack(spacing: 8) {
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

            // Hidden while rearranging. Neither is any use mid-rearrange, and dropping them
            // takes the cluster from three buttons to one — which is exactly when the tile
            // underneath needs the room for its own controls.
            if !model.isEditing {
                circularButton(systemImage: "gearshape", label: "Settings", isOn: showingSettings) {
                    showingSettings = true
                }

                circularButton(systemImage: "square.grid.2x2", label: "Layouts", isOn: showingLibrary) {
                    showingLibrary = true
                }
            }

            if services.location.isDriving {
                // Explains the missing control rather than leaving a gap where the
                // rearrange button was.
                Label("Driving", systemImage: "car.fill")
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: DashMetrics.minimumHitTarget)
                    .background(theme.tile, in: Capsule())
                    .accessibilityLabel("Rearranging is disabled while driving")
            } else {
                circularButton(
                    systemImage: model.isEditing ? "checkmark" : "slider.horizontal.3",
                    label: model.isEditing ? "Done rearranging" : "Rearrange tiles",
                    isOn: model.isEditing
                ) {
                    withAnimation(.snappy(duration: 0.25)) { model.isEditing.toggle() }
                    Haptics.edit()
                }
            }
        }
        .padding(5)
        .background(theme.background.opacity(0.78), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.tileStroke))
        .animation(.snappy(duration: 0.2), value: model.isEditing)
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
                                    services.registry.title(for: pane.sectionID),
                                    systemImage: services.registry.systemImage(for: pane.sectionID)
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
