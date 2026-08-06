import Foundation

/// How small each built-in section may be drawn.
///
/// These live in Core, not next to their views, for two reasons. The bundled presets
/// need them in order to be checked for fit on Linux, and having exactly one definition
/// means a section cannot declare one minimum to the registry and imply another to the
/// preset that uses it. `SectionDescriptor` reads from here.
///
/// The numbers are floors for *legibility at a glance while moving*, not for "the view
/// does not crash". A map that is technically rendered but too small to orient yourself
/// with is worse than a map you chose not to put on screen.
public enum SectionMetrics {
    public static let minimumSizes: [SectionID: LayoutSize] = [
        .map: LayoutSize(width: 260, height: 180),
        .music: LayoutSize(width: 240, height: 190),
        .nowPlaying: LayoutSize(width: 220, height: 96),
        .gauges: LayoutSize(width: 190, height: 150),
        // Tall enough that the WeatherKit attribution logo and legal link are never
        // clipped. That is a licensing requirement, not a design preference — do not
        // shrink this to make a layout fit.
        .weather: LayoutSize(width: 210, height: 170),
        .clock: LayoutSize(width: 150, height: 90),
        .phone: LayoutSize(width: 240, height: 200),
        .messages: LayoutSize(width: 240, height: 200),
        .youtube: LayoutSize(width: 280, height: 170)
    ]

    public static let builtInPolicy = MinimumSizePolicy.table(minimumSizes)

    public static func minimumSize(for sectionID: SectionID) -> LayoutSize {
        minimumSizes[sectionID] ?? .default
    }
}
