import SwiftUI
import CarDashCore

/// Display names and symbols for the built-in sections.
///
/// Deliberately minimal: this is what the layout editor needs in order to label a tile
/// and offer a list of things to put in one. Phase 2 grows this into a full
/// `SectionRegistry` that also supplies the views, minimum sizes and capabilities; until
/// there are views to register, that would be a registry of nothing.
public enum SectionCatalog {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: SectionID
        public let title: String
        public let systemImage: String
        /// What the tile can actually do — shown in the picker so it is clear before
        /// choosing, not after. Several of these are constrained by what iOS permits.
        public let blurb: String
        /// Phases still to land. Nil once a section is real.
        public let comingIn: String?
    }

    public static let entries: [Entry] = [
        Entry(id: .map, title: "Map", systemImage: "map.fill",
              blurb: "Position, search and directions.", comingIn: "Phase 3"),
        Entry(id: .music, title: "Music", systemImage: "music.note",
              blurb: "Spotify, Apple Music, YouTube or your own files.", comingIn: "Phase 4"),
        Entry(id: .nowPlaying, title: "Now Playing", systemImage: "waveform",
              blurb: "Compact transport bar for whatever is playing.", comingIn: "Phase 4"),
        Entry(id: .gauges, title: "Gauges", systemImage: "gauge.with.dots.needle.50percent",
              blurb: "Speed, heading, altitude and trip meter, from GPS.", comingIn: "Phase 2"),
        Entry(id: .weather, title: "Weather", systemImage: "cloud.sun.fill",
              blurb: "Current conditions and the next few hours.", comingIn: "Phase 2"),
        Entry(id: .clock, title: "Clock", systemImage: "clock.fill",
              blurb: "The time, large enough to read at a glance.", comingIn: "Phase 2"),
        Entry(id: .phone, title: "Phone", systemImage: "phone.fill",
              blurb: "Favourites you can dial with one tap.", comingIn: "Phase 6"),
        Entry(id: .messages, title: "Messages", systemImage: "message.fill",
              blurb: "Prefilled replies. iOS still requires you to tap send.", comingIn: "Phase 6"),
        Entry(id: .youtube, title: "YouTube", systemImage: "play.rectangle.fill",
              blurb: "Foreground playback only — audio stops when you leave.", comingIn: "Phase 7")
    ]

    private static let byID: [SectionID: Entry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.id, $0) }
    )

    public static func entry(for id: SectionID) -> Entry? {
        byID[id]
    }

    /// A layout saved by a build that had a section this one does not still loads; the
    /// tile shows the raw identifier and offers to be replaced.
    public static func title(for id: SectionID) -> String {
        byID[id]?.title ?? id.rawValue
    }

    public static func systemImage(for id: SectionID) -> String {
        byID[id]?.systemImage ?? "questionmark.square.dashed"
    }

    public static func isKnown(_ id: SectionID) -> Bool {
        byID[id] != nil
    }
}
