import Foundation
import Observation
import CarDashCore

/// The shared objects every section is handed.
///
/// One place to construct the real graph, and one place for previews and tests to
/// substitute stubs. Sections reach services only through `PaneContext`, so nothing
/// inside a tile ever reaches for a singleton.
@MainActor
@Observable
public final class AppServices {
    public let location: LocationService
    public let theme: ThemeController
    public let weather: WeatherStore
    public let registry: SectionRegistry
    public let route: RouteService
    public let search: SearchService
    public let announcer: NavigationAnnouncer
    public let audio: AudioCoordinator
    /// Shared by the Phone and Messages tiles — they are the same people.
    public let favourites: FavouritesStore
    /// Puts the next manoeuvre on the lock screen, where the dashboard cannot go.
    public let liveActivity: NavigationActivityController

    public var unitSystem: UnitSystem {
        didSet {
            guard unitSystem != oldValue else { return }
            defaults.set(unitSystem.rawValue, forKey: Self.unitKey)
        }
    }

    /// How tightly the dashboard is packed. Read by the views through the environment and by
    /// the layout solver through `LayoutModel`, so changing it re-solves and redraws.
    public var density: DisplayDensity {
        didSet {
            guard density != oldValue else { return }
            defaults.set(density.rawValue, forKey: Self.densityKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let unitKey = "cardash.unitSystem"
    @ObservationIgnored private static let densityKey = "cardash.density"

    /// Every dependency is optional rather than defaulted, because a default argument
    /// expression is evaluated in a nonisolated context and none of these main-actor
    /// types can be constructed there. Building them in the body is equivalent and
    /// compiles.
    public init(
        location: LocationService? = nil,
        theme: ThemeController? = nil,
        weather: WeatherStore? = nil,
        registry: SectionRegistry? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.location = location ?? LocationService()
        self.theme = theme ?? ThemeController()
        self.weather = weather ?? WeatherStore(
            provider: CachingWeatherProvider(wrapping: OpenMeteoProvider())
        )
        self.registry = registry ?? SectionRegistry()
        self.route = RouteService()
        self.search = SearchService()
        self.announcer = NavigationAnnouncer()
        self.audio = AudioCoordinator()
        self.favourites = FavouritesStore(defaults: defaults)
        self.liveActivity = NavigationActivityController()
        self.defaults = defaults
        self.unitSystem = defaults.string(forKey: Self.unitKey)
            .flatMap(UnitSystem.init(rawValue:))
            ?? Self.regionDefault
        // An unreadable stored value — written by a build with a level this one dropped —
        // falls back rather than refusing to launch.
        self.density = defaults.string(forKey: Self.densityKey)
            .flatMap(DisplayDensity.init(rawValue:))
            ?? .default
    }

    /// Best guess from the device's region, since asking on first launch would be a
    /// setup screen for a single choice the user can change in settings.
    private static var regionDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    public func start() {
        location.start()
        theme.refresh()
        // A Live Activity outlives the process that started it, so a route abandoned by a crash
        // or a force-quit leaves a banner on the lock screen that nothing else will ever clear.
        liveActivity.endOrphanedActivities()
    }

    /// Called when a fix arrives.
    ///
    /// Navigation is driven from here rather than from the map tile, because a route
    /// must keep running whether or not the map happens to be on screen — the driver may
    /// well have swapped it for the music tile mid-journey.
    public func positionChanged(to coordinate: Coordinate?) {
        theme.updatePosition(coordinate)
        guard let coordinate, let timestamp = location.updatedAt else { return }

        search.setRegion(around: coordinate)

        let fix = GeoFix(
            coordinate: coordinate,
            course: location.course,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: timestamp
        )
        for prompt in route.ingest(fix) {
            announcer.announce(prompt)
        }

        syncLiveActivity(now: timestamp)
    }

    /// Keeps the lock screen in step with the route.
    ///
    /// Driven from the position stream rather than from the map tile, for the same reason
    /// navigation itself is: the lock screen has to keep working when the map is not on screen,
    /// and by definition it has to keep working when *nothing* is on screen.
    ///
    /// The rate limiting lives in the controller, which compares rendered strings rather than
    /// raw metres — moving twelve metres changes the number and changes nothing anyone sees.
    private func syncLiveActivity(now: Date) {
        guard let guidance = route.guidance else {
            if liveActivity.isRunning { liveActivity.end() }
            return
        }

        let state = NavigationActivityState.from(guidance, units: unitSystem, now: now)

        guard liveActivity.isRunning else {
            liveActivity.start(
                destination: route.destinationName ?? "Destination",
                state: state
            )
            return
        }

        if guidance.hasArrived {
            // Ends showing the arrival rather than the last turn, and leaves it up a minute.
            liveActivity.finish(with: state)
        } else {
            liveActivity.update(state)
        }
    }
}

/// Shared weather state.
///
/// One store rather than per-tile fetching: two weather tiles, or a weather tile plus a
/// map that wants conditions, should be one request. Combined with the caching provider
/// this keeps a full day's driving at roughly a hundred calls.
@MainActor
@Observable
public final class WeatherStore {
    public private(set) var snapshot: WeatherSnapshot?
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    @ObservationIgnored private let provider: any WeatherProviding
    @ObservationIgnored private var lastRequested: Coordinate?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(provider: any WeatherProviding) {
        self.provider = provider
    }

    /// Fetches if the position has moved far enough to matter, or if there is nothing
    /// yet. The caching provider handles freshness; this only avoids pointless calls.
    public func refresh(for coordinate: Coordinate?, force: Bool = false) {
        guard let coordinate, coordinate.isValid else { return }
        let key = coordinate.rounded()
        guard force || key != lastRequested || snapshot == nil else { return }

        lastRequested = key
        task?.cancel()
        task = Task { [provider] in
            isLoading = true
            defer { isLoading = false }
            do {
                let result = try await provider.snapshot(for: key)
                guard !Task.isCancelled else { return }
                snapshot = result
                lastError = nil
            } catch is CancellationError {
                return
            } catch {
                // Only surfaced when there is nothing to show. A failed refresh with a
                // usable previous forecast is not worth an error on a dashboard.
                if snapshot == nil {
                    lastError = "Weather unavailable"
                }
            }
        }
    }
}
