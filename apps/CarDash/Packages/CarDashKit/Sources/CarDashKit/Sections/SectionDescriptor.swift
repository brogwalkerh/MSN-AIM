import SwiftUI
import CarDashCore

public struct SectionCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Owns or drives audio. The audio coordinator arbitrates between these.
    public static let producesAudio = SectionCapabilities(rawValue: 1 << 0)
    /// Wants location updates running while it is on screen.
    public static let needsLocation = SectionCapabilities(rawValue: 1 << 1)
    public static let needsNetwork = SectionCapabilities(rawValue: 1 << 2)
    /// Draws to the tile's edges — no padding, no inset chrome. The map.
    public static let fullBleed = SectionCapabilities(rawValue: 1 << 3)
    /// Two of these on one dashboard would be pointless or actively wrong.
    public static let singleton = SectionCapabilities(rawValue: 1 << 4)
    /// Not built yet. Shown in the picker, marked as such, renders a placeholder.
    public static let comingSoon = SectionCapabilities(rawValue: 1 << 5)
}

/// What a tile knows about the situation it is being drawn in.
public struct PaneEnvironment: Hashable, Sendable {
    public let size: LayoutSize
    public let isEditing: Bool
    public let canvasClass: CanvasClass

    public init(size: LayoutSize, isEditing: Bool, canvasClass: CanvasClass) {
        self.size = size
        self.isEditing = isEditing
        self.canvasClass = canvasClass
    }

    /// Too short for a heading plus a body. Sections drop to a single line rather than
    /// clipping — a tile can legitimately be 96 points tall.
    public var isCompact: Bool { size.height < 150 }
    public var isNarrow: Bool { size.width < 240 }
}

/// Everything a section's view is handed.
@MainActor
public struct PaneContext {
    public let paneID: PaneID
    public let services: AppServices
    /// The section's own persisted settings, saved with the layout. Opaque to the layout
    /// engine — see `SectionState`.
    public let state: Binding<SectionState>
    public let environment: PaneEnvironment

    public init(
        paneID: PaneID,
        services: AppServices,
        state: Binding<SectionState>,
        environment: PaneEnvironment
    ) {
        self.paneID = paneID
        self.services = services
        self.state = state
        self.environment = environment
    }
}

/// A section, as a value.
///
/// A value rather than a protocol with an associated view type, so that a heterogeneous
/// registry needs no existential gymnastics and a section can be swapped for a
/// placeholder with no ceremony. The layout engine never sees this — it stores only the
/// `SectionID` string, which is what keeps it Linux-testable.
public struct SectionDescriptor: Identifiable, Sendable {
    public let id: SectionID
    public let title: String
    public let systemImage: String
    /// One honest line about what the tile does, shown in the picker. Several sections
    /// are constrained by what iOS permits, and it is better to say so before the user
    /// chooses than after.
    public let blurb: String
    public let minimumSize: LayoutSize
    public let capabilities: SectionCapabilities
    public let makeView: @MainActor @Sendable (PaneContext) -> AnyView

    public init(
        id: SectionID,
        title: String,
        systemImage: String,
        blurb: String,
        minimumSize: LayoutSize? = nil,
        capabilities: SectionCapabilities = [],
        makeView: @escaping @MainActor @Sendable (PaneContext) -> AnyView
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.blurb = blurb
        // Defaults to the shared table in CarDashCore, so a section cannot declare one
        // minimum to the registry and imply another to the preset that uses it.
        self.minimumSize = minimumSize ?? SectionMetrics.minimumSize(for: id)
        self.capabilities = capabilities
        self.makeView = makeView
    }

    public var isComingSoon: Bool { capabilities.contains(.comingSoon) }

    /// A descriptor for a section that has not been built yet.
    static func placeholder(
        id: SectionID,
        title: String,
        systemImage: String,
        blurb: String,
        arrivesIn: String,
        capabilities: SectionCapabilities = []
    ) -> SectionDescriptor {
        SectionDescriptor(
            id: id,
            title: title,
            systemImage: systemImage,
            blurb: blurb,
            capabilities: capabilities.union(.comingSoon)
        ) { context in
            AnyView(
                SectionPlaceholderView(
                    title: title,
                    systemImage: systemImage,
                    detail: "Arrives in \(arrivesIn)",
                    environment: context.environment
                )
            )
        }
    }
}
