import SwiftUI
import Observation
import CarDashCore

/// Chooses between the day and night appearance.
///
/// Driven by the sun, not by the system's light/dark setting. What matters in a car is
/// whether it is dark outside; a phone left in dark mode all summer would otherwise
/// blast a black-on-white map at midnight.
@MainActor
@Observable
public final class ThemeController {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        case auto
        case day
        case night

        public var label: String {
            switch self {
            case .auto: return "Automatic"
            case .day: return "Day"
            case .night: return "Night"
            }
        }
    }

    public var mode: Mode = .auto {
        didSet { recompute() }
    }

    public private(set) var theme: DashTheme = .night
    public private(set) var isNight = true

    @ObservationIgnored private var coordinate: Coordinate?
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
        recompute()
    }

    /// Fed from `LocationService`. Until there is a fix, `auto` falls back to a plain
    /// clock-based guess rather than picking one and staying there.
    public func updatePosition(_ coordinate: Coordinate?) {
        guard coordinate != self.coordinate else { return }
        self.coordinate = coordinate
        recompute()
    }

    /// Called on a timer and when the app returns to the foreground, so the switch
    /// happens during a drive rather than only at launch.
    public func refresh() {
        recompute()
    }

    private func recompute() {
        let now = clock()
        switch mode {
        case .day:
            isNight = false
        case .night:
            isNight = true
        case .auto:
            if let coordinate, coordinate.isValid {
                isNight = !SolarCalculator.isDaylight(at: coordinate, on: now)
            } else {
                // No position yet. A crude local-hour split is wrong near the poles and
                // at the edges of a time zone, but it is only ever the first few seconds
                // after launch, and it beats defaulting to daylight at midnight.
                let hour = Calendar.current.component(.hour, from: now)
                isNight = hour < 6 || hour >= 20
            }
        }
        theme = isNight ? .night : .day
    }
}
