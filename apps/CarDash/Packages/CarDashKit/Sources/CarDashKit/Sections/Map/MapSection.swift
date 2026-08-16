import SwiftUI
import MapKit
import CarDashCore

enum MapSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .map,
            title: "Map",
            systemImage: "map.fill",
            blurb: "Your position, search, and turn-by-turn directions.",
            capabilities: [.needsLocation, .needsNetwork, .fullBleed, .singleton]
        ) { context in
            AnyView(MapPaneView(context: context))
        }
    }
}

struct MapPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isFollowing = true
    @State private var showingSearch = false

    private var location: LocationService { context.services.location }
    private var route: RouteService { context.services.route }
    private var units: UnitSystem { context.services.unitSystem }
    private var isNight: Bool { context.services.theme.isNight }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map
            if route.phase == .navigating { instructionBanner }
            controls
        }
        .sheet(isPresented: $showingSearch) {
            DestinationSearchSheet(context: context)
        }
        .onChange(of: location.coordinate) { _, coordinate in
            guard isFollowing, let coordinate else { return }
            follow(coordinate)
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()

            if !route.routePolyline.isEmpty {
                MapPolyline(coordinates: route.routePolyline)
                    .stroke(
                        theme.accent,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        // At night the map is the brightest thing in the car, so points of interest are
        // dropped entirely: they are the densest, least useful pixels on the screen and
        // every one of them is glare on the windscreen.
        .mapStyle(
            .standard(
                elevation: .flat,
                pointsOfInterest: isNight ? .excludingAll : .including([.gasStation, .parking, .evCharger])
            )
        )
        .mapControls {
            MapCompass()
        }
        // Any pan or zoom hands control back to the driver until they ask for the
        // camera to follow again.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { _ in isFollowing = false }
        )
        .ignoresSafeArea()
    }

    private func follow(_ coordinate: Coordinate) {
        withAnimation(.easeOut(duration: 0.6)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: coordinate.clCoordinate,
                    // Pull back at speed so more of the road ahead is visible.
                    distance: route.phase == .navigating ? 900 : 1600,
                    // Below walking pace `course` is noise, so the map stops spinning
                    // and settles north-up rather than twitching at a red light.
                    heading: location.course ?? 0,
                    pitch: route.phase == .navigating ? 45 : 0
                )
            )
        }
    }

    // MARK: - Guidance

    @ViewBuilder
    private var instructionBanner: some View {
        if let guidance = route.guidance {
            VStack(alignment: .leading, spacing: 2) {
                if guidance.isOffRoute {
                    Label("Off route — recalculating", systemImage: "exclamationmark.triangle.fill")
                        .font(DashFont.label())
                        .foregroundStyle(theme.destructive)
                } else {
                    Text(UnitFormatting.distance(meters: guidance.distanceToManeuver, system: units))
                        .font(DashFont.value(22))
                        .foregroundStyle(theme.accent)
                    Text(guidance.currentInstruction ?? "")
                        .font(DashFont.label(15))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                }

                Text(
                    "\(UnitFormatting.duration(seconds: guidance.estimatedTimeRemaining)) · "
                    + UnitFormatting.distance(meters: guidance.distanceRemaining, system: units)
                )
                .font(DashFont.label(11))
                .foregroundStyle(theme.secondaryText)
            }
            .padding(10)
            .background(theme.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
            // The inner 10 is the callout's own text inset; this is its distance from the
            // tile edge. They used to be 10 and 8, which floated the guidance card 18 points
            // into a map that is deliberately full-bleed.
            .panePadding()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                if route.phase == .navigating {
                    mapButton("xmark", label: "End navigation") {
                        route.stop()
                        context.services.announcer.stop()
                    }
                    // MapKit gives route data but no lane guidance, junction views, live
                    // traffic or speed limits. On an unfamiliar road that matters, so
                    // handing off to Apple Maps is offered plainly rather than hidden.
                    mapButton("arrow.triangle.turn.up.right.circle", label: "Open in Apple Maps") {
                        openInAppleMaps()
                    }
                } else {
                    mapButton("magnifyingglass", label: "Search for a destination") {
                        showingSearch = true
                    }
                    .disabled(location.isDriving)
                    .opacity(location.isDriving ? 0.4 : 1)
                }

                Spacer()

                if !isFollowing {
                    mapButton("location.fill", label: "Recentre") {
                        isFollowing = true
                        if let coordinate = location.coordinate { follow(coordinate) }
                    }
                }
            }
            .panePadding()
        }
    }

    private func mapButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .frame(width: 48, height: 48)
                .background(theme.background.opacity(0.8), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func openInAppleMaps() {
        guard let coordinate = location.coordinate else { return }
        let item = coordinate.mapItem
        item.name = route.destinationName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

/// Destination search. Only reachable while stopped — see the disabled state above.
struct DestinationSearchSheet: View {
    let context: PaneContext

    @Environment(\.dismiss) private var dismiss
    @State private var isStarting = false

    private var search: SearchService { context.services.search }

    var body: some View {
        NavigationStack {
            List {
                if search.suggestions.isEmpty, !search.query.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                }
                ForEach(search.suggestions) { suggestion in
                    Button {
                        start(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(
                text: Binding(get: { search.query }, set: { search.query = $0 }),
                prompt: "Where to?"
            )
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        search.clear()
                        dismiss()
                    }
                }
            }
            .overlay {
                if isStarting { ProgressView().controlSize(.large) }
            }
        }
    }

    private func start(_ suggestion: SearchService.Suggestion) {
        guard let origin = context.services.location.coordinate else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            guard let item = await search.resolve(suggestion) else { return }
            await context.services.route.startNavigating(to: item, from: origin)
            search.clear()
            dismiss()
        }
    }
}
