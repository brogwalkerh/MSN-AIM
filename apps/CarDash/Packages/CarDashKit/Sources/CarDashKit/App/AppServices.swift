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

    public var unitSystem: UnitSystem {
        didSet {
            guard unitSystem != oldValue else { return }
            defaults.set(unitSystem.rawValue, forKey: Self.unitKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let unitKey = "cardash.unitSystem"

    public init(
        location: LocationService = LocationService(),
        theme: ThemeController = ThemeController(),
        weather: WeatherStore? = nil,
        registry: SectionRegistry = SectionRegistry(),
        defaults: UserDefaults = .standard
    ) {
        self.location = location
        self.theme = theme
        self.weather = weather ?? WeatherStore(
            provider: CachingWeatherProvider(wrapping: OpenMeteoProvider())
        )
        self.registry = registry
        self.defaults = defaults
        self.unitSystem = defaults.string(forKey: Self.unitKey)
            .flatMap(UnitSystem.init(rawValue:))
            ?? Self.regionDefault
    }

    /// Best guess from the device's region, since asking on first launch would be a
    /// setup screen for a single choice the user can change in settings.
    private static var regionDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    public func start() {
        location.start()
        theme.refresh()
    }

    /// Called when a fix arrives, to keep the theme and the forecast tracking the car.
    public func positionChanged(to coordinate: Coordinate?) {
        theme.updatePosition(coordinate)
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
