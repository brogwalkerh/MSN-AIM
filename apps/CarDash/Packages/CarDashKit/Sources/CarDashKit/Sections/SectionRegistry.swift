import SwiftUI
import CarDashCore
import Observation

/// Everything that can go in a tile.
///
/// Adding a section is three edits and no project-file change: write the descriptor next
/// to its view, add it to `builtIn`, add a `#Preview`. The buildable-folder setup means
/// the new file is compiled automatically.
@MainActor
@Observable
public final class SectionRegistry {
    public private(set) var descriptors: [SectionID: SectionDescriptor] = [:]
    /// Registration order, which is the order the picker offers them in.
    public private(set) var order: [SectionID] = []

    public init(_ descriptors: [SectionDescriptor] = SectionRegistry.builtIn) {
        for descriptor in descriptors {
            register(descriptor)
        }
    }

    public func register(_ descriptor: SectionDescriptor) {
        if descriptors[descriptor.id] == nil {
            order.append(descriptor.id)
        }
        descriptors[descriptor.id] = descriptor
    }

    /// Nil for a section this build does not have — a layout saved by a newer build, or
    /// one whose identifier was renamed. Callers render `MissingSectionView`.
    public func descriptor(for id: SectionID) -> SectionDescriptor? {
        descriptors[id]
    }

    public var all: [SectionDescriptor] {
        order.compactMap { descriptors[$0] }
    }

    /// Ready sections first, then the ones still to come — so the picker leads with
    /// things that actually do something.
    public var pickerOrder: [SectionDescriptor] {
        all.filter { !$0.isComingSoon } + all.filter(\.isComingSoon)
    }

    public func title(for id: SectionID) -> String {
        descriptors[id]?.title ?? id.rawValue
    }

    public func systemImage(for id: SectionID) -> String {
        descriptors[id]?.systemImage ?? "questionmark.square.dashed"
    }

    /// Feeds the layout engine's minimum-size fold.
    public var minimumSizePolicy: MinimumSizePolicy {
        // Captures a snapshot rather than self: the policy is Sendable and is handed to
        // Core, which must not hold a reference to a main-actor object.
        let sizes = descriptors.mapValues(\.minimumSize)
        return MinimumSizePolicy { sizes[$0] ?? SectionMetrics.minimumSize(for: $0) }
    }

    // MARK: - The built-in set

    public static var builtIn: [SectionDescriptor] {
        [
            MapSection.descriptor,
            MusicSection.descriptor,
            NowPlayingSection.descriptor,
            GaugesSection.descriptor,
            WeatherSection.descriptor,
            ClockSection.descriptor,
            PhoneSection.descriptor,
            MessagesSection.descriptor,
            YouTubeSection.descriptor
        ]
    }
}

// MARK: - Sections still to be built
//
// Real descriptors rather than a special case in the registry, so the picker, the
// minimum-size policy and the preset validation all treat them uniformly. Each is
// replaced in place when its phase lands.

enum MapSection {
    static var descriptor: SectionDescriptor {
        .placeholder(
            id: .map,
            title: "Map",
            systemImage: "map.fill",
            blurb: "Your position, search, and turn-by-turn directions.",
            arrivesIn: "Phase 3",
            capabilities: [.needsLocation, .needsNetwork, .fullBleed, .singleton]
        )
    }
}

enum MusicSection {
    static var descriptor: SectionDescriptor {
        .placeholder(
            id: .music,
            title: "Music",
            systemImage: "music.note",
            blurb: "Spotify, your Apple Music library, YouTube, or your own files.",
            arrivesIn: "Phase 4",
            capabilities: [.producesAudio, .needsNetwork, .singleton]
        )
    }
}

enum NowPlayingSection {
    static var descriptor: SectionDescriptor {
        .placeholder(
            id: .nowPlaying,
            title: "Now Playing",
            systemImage: "waveform",
            blurb: "A compact transport bar for whatever is playing.",
            arrivesIn: "Phase 4",
            capabilities: [.singleton]
        )
    }
}

enum PhoneSection {
    static var descriptor: SectionDescriptor {
        .placeholder(
            id: .phone,
            title: "Phone",
            systemImage: "phone.fill",
            blurb: "Favourites you can dial with one tap.",
            arrivesIn: "Phase 6",
            capabilities: [.singleton]
        )
    }
}

enum MessagesSection {
    static var descriptor: SectionDescriptor {
        .placeholder(
            id: .messages,
            title: "Messages",
            systemImage: "message.fill",
            blurb: "Prefilled replies. iOS still requires you to tap send.",
            arrivesIn: "Phase 6",
            capabilities: [.singleton]
        )
    }
}

enum YouTubeSection {
    static var descriptor: SectionDescriptor {
        .placeholder(
            id: .youtube,
            title: "YouTube",
            systemImage: "play.rectangle.fill",
            blurb: "Foreground only — audio stops when you leave the app.",
            arrivesIn: "Phase 7",
            capabilities: [.producesAudio, .needsNetwork, .singleton]
        )
    }
}
