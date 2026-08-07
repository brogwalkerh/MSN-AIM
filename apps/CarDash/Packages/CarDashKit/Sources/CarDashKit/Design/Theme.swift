import SwiftUI
import CarDashCore

/// Colours and type for the dashboard.
///
/// Two variants rather than a light/dark system pair, because the relevant question in a
/// car is not the user's OS appearance setting but whether it is dark outside. Phase 2
/// wires this to `SolarCalculator`; for now `.night` is the default because that is the
/// harder case to get right and the one that matters most.
public struct DashTheme: Sendable, Hashable {
    public var background: Color
    public var tile: Color
    public var tileStroke: Color
    public var accent: Color
    public var primaryText: Color
    public var secondaryText: Color
    public var divider: Color
    public var dividerActive: Color
    public var destructive: Color

    /// True black rather than dark grey: OLED pixels that are off emit nothing, which
    /// removes glare on the windscreen at night instead of merely reducing it.
    public static let night = DashTheme(
        background: .black,
        tile: Color.white.opacity(0.06),
        tileStroke: Color.white.opacity(0.10),
        accent: Color(red: 1.0, green: 0.62, blue: 0.18),
        primaryText: Color.white.opacity(0.92),
        secondaryText: Color.white.opacity(0.55),
        divider: Color.white.opacity(0.10),
        dividerActive: Color(red: 1.0, green: 0.62, blue: 0.18),
        destructive: Color(red: 1.0, green: 0.35, blue: 0.30)
    )

    public static let day = DashTheme(
        background: Color(white: 0.06),
        tile: Color.white.opacity(0.11),
        tileStroke: Color.white.opacity(0.16),
        accent: Color(red: 1.0, green: 0.69, blue: 0.0),
        primaryText: .white,
        secondaryText: Color.white.opacity(0.65),
        divider: Color.white.opacity(0.16),
        dividerActive: Color(red: 1.0, green: 0.69, blue: 0.0),
        destructive: Color(red: 1.0, green: 0.42, blue: 0.36)
    )
}

extension EnvironmentValues {
    @Entry public var dashTheme: DashTheme = .night

    /// How tightly to pack things. Injected once by `DashboardView` and read by the tile
    /// chrome and every section, so one setting moves the whole dashboard at once.
    @Entry public var dashDensity: DisplayDensity = .default
}

extension View {
    /// The standard inset from a tile's edge to its content.
    ///
    /// Every section used to write its own `.padding(8)` or `.padding(10)`, which meant the
    /// dashboard had no single spacing to change and the sections quietly disagreed with each
    /// other by a couple of points. This is that number, once.
    public func panePadding(_ edges: Edge.Set = .all) -> some View {
        modifier(PanePadding(edges: edges))
    }
}

struct PanePadding: ViewModifier {
    let edges: Edge.Set
    @Environment(\.dashDensity) private var density

    func body(content: Content) -> some View {
        content.padding(edges, density.panePadding)
    }
}

/// Type sized for glancing, not reading.
///
/// A dashboard is read in fractions of a second from arm's length in a moving vehicle,
/// so everything here is larger than an equivalent phone UI would be, and rounded —
/// which is measurably faster to recognise at a glance than the default face.
public enum DashFont {
    public static func value(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    public static let paneTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
    public static let bigReadout = Font.system(size: 64, weight: .bold, design: .rounded)
}

public enum DashMetrics {
    /// Minimum tappable edge. Apple's floor for CarPlay is 44; a bumpy road and a
    /// mounted phone argue for more.
    public static let minimumHitTarget: CGFloat = 60
}
