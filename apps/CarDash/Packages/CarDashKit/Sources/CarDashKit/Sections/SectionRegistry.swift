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

    /// Nil means the built-in set. It cannot be a default *argument* — default
    /// expressions are evaluated in a nonisolated context, and `builtIn` is
    /// main-actor-isolated like the rest of this class.
    public init(_ descriptors: [SectionDescriptor]? = nil) {
        for descriptor in descriptors ?? Self.builtIn {
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
// replaced in place when its phase lands — Phone and Messages have been, and now live
// next to their views like every other real section.

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
