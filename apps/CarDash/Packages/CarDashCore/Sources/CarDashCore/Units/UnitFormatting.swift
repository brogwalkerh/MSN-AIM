import Foundation

public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric
    case imperial

    public var speedLabel: String { self == .metric ? "km/h" : "mph" }
}

/// Number formatting for a dashboard.
///
/// Written by hand rather than with `MeasurementFormatter` for two reasons: the output
/// needs to be glanceable rather than grammatical ("62" in huge type with a small
/// "mph", not "62 miles per hour"), and hand-written arithmetic is identical on Linux,
/// where the ICU-backed formatters behave differently from Apple platforms.
public enum UnitFormatting {
    public static let metresPerSecondToKPH = 3.6
    public static let metresPerSecondToMPH = 2.236_936
    public static let metresToMiles = 0.000_621_371
    public static let metresToFeet = 3.280_84

    /// Speed as a bare integer, for display beside a separate unit label.
    ///
    /// Rounded, not truncated: a speedometer reading 59 at 59.7 km/h feels broken.
    /// Negative or unknown speeds come back as nil so the gauge can show a placeholder
    /// rather than a confident zero — CoreLocation reports -1 when it does not know,
    /// and "0" is a very different claim from "no idea".
    public static func speedValue(metersPerSecond: Double?, system: UnitSystem) -> Int? {
        guard let metersPerSecond, metersPerSecond >= 0, metersPerSecond.isFinite else {
            return nil
        }
        let converted = metersPerSecond * (system == .metric ? metresPerSecondToKPH : metresPerSecondToMPH)
        return Int(converted.rounded())
    }

    /// Distance for a route or a trip meter, with the precision changing by magnitude —
    /// "400 m" up close, "12.4 km" further out, "148 km" further still.
    public static func distance(meters: Double, system: UnitSystem) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }

        switch system {
        case .metric:
            if meters < 950 {
                return "\(Int((meters / 10).rounded() * 10)) m"
            }
            let km = meters / 1000
            return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"

        case .imperial:
            let miles = meters * metresToMiles
            if miles < 0.2 {
                let feet = meters * metresToFeet
                return "\(Int((feet / 10).rounded() * 10)) ft"
            }
            return miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
        }
    }

    /// A duration as a driver reads it: "8 min", "1 hr 24 min".
    public static func duration(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 60 {
            return "\(max(totalMinutes, 1)) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    /// Compass point for a heading in degrees, for the heading gauge. Sixteen points is
    /// as fine as is readable at a glance.
    public static func compassPoint(degrees: Double) -> String {
        guard degrees.isFinite else { return "—" }
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int((positive / 22.5).rounded()) % points.count
        return points[index]
    }

    public static func temperature(celsius: Double, system: UnitSystem) -> String {
        guard celsius.isFinite else { return "—" }
        let value = system == .metric ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }
}
