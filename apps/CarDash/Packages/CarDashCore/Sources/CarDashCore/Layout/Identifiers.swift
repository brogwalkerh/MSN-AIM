import Foundation

/// Identifies a *placed tile*, not what is in it.
///
/// The distinction matters for animation: swapping two tiles moves their `PaneID`s with
/// their content, so SwiftUI can animate the exchange rather than cross-fading two
/// stationary boxes.
public struct PaneID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// Identifies a divider — equivalently, the split node that owns it.
public struct DividerID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// Identifies a *kind* of section — "map", "music" — as a stable string.
///
/// Core stores only this. It has no idea what a section looks like, which is what keeps
/// the layout engine free of SwiftUI and therefore testable on Linux. The app maps these
/// to views in `SectionRegistry`.
///
/// Stability is a persistence contract: these strings are written into saved layouts, so
/// renaming one orphans every tile using it. `MissingSectionView` handles that gracefully
/// rather than failing the whole document, but it is still a migration.
public struct SectionID: Hashable, Sendable, Codable, RawRepresentable,
                         ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

extension SectionID {
    // The identifiers the built-in sections use. They live in Core rather than beside
    // their views because the bundled presets reference them, and a preset that names a
    // section nobody registered is a bug worth catching in a test rather than on a
    // dashboard.
    public static let map: SectionID = "map"
    public static let music: SectionID = "music"
    public static let nowPlaying: SectionID = "nowPlaying"
    public static let gauges: SectionID = "gauges"
    public static let weather: SectionID = "weather"
    public static let clock: SectionID = "clock"
    public static let phone: SectionID = "phone"
    public static let messages: SectionID = "messages"
    public static let youtube: SectionID = "youtube"

    /// Every section the app ships, in the order they are offered when adding a tile.
    public static let builtIn: [SectionID] = [
        .map, .music, .nowPlaying, .gauges, .weather, .clock, .phone, .messages, .youtube
    ]
}

/// A section's own persisted state, opaque to the layout engine.
///
/// Keeping this a blob is what makes saved layouts forward- and backward-compatible: a
/// document written by a build that had a section this build does not can still be
/// decoded, because nothing here needs to understand the payload.
public struct SectionState: Hashable, Sendable, Codable {
    public var data: Data

    public init(data: Data = Data()) {
        self.data = data
    }

    public static let empty = SectionState()

    public var isEmpty: Bool { data.isEmpty }

    public init(from decoder: any Decoder) throws {
        data = try decoder.singleValueContainer().decode(Data.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }

    /// Decodes the payload, returning nil for empty state or anything this build cannot
    /// read. Callers fall back to their own defaults — a section whose stored settings
    /// were written by a newer build should come up with defaults, not refuse to load.
    public func decoded<T: Decodable>(as type: T.Type = T.self) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func encoding(_ value: some Encodable) -> SectionState {
        guard let data = try? JSONEncoder().encode(value) else { return .empty }
        return SectionState(data: data)
    }
}
