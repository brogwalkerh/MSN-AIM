import Foundation

/// A Spotify Connect device.
public struct SpotifyDevice: Hashable, Sendable, Identifiable, Decodable {
    public let id: String?
    public let name: String
    public let type: String
    public let isActive: Bool
    public let isRestricted: Bool
    public let volumePercent: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case isActive = "is_active"
        case isRestricted = "is_restricted"
        case volumePercent = "volume_percent"
    }

    public init(
        id: String?,
        name: String,
        type: String,
        isActive: Bool,
        isRestricted: Bool = false,
        volumePercent: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isActive = isActive
        self.isRestricted = isRestricted
        self.volumePercent = volumePercent
    }

    /// Decoded field by field rather than synthesised.
    ///
    /// A synthesised initializer treats every absent non-optional as a hard failure, and a
    /// device object is the one place Spotify's shape varies most — Connect speakers,
    /// cast targets and the desktop client do not all report the same keys. One missing
    /// `is_restricted` would otherwise fail the entire `GET /me/player` response and make
    /// the tile claim Spotify is broken.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown device"
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Unknown"
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isRestricted = try container.decodeIfPresent(Bool.self, forKey: .isRestricted) ?? false
        volumePercent = try container.decodeIfPresent(Int.self, forKey: .volumePercent)
    }

    /// Spotify marks some devices as restricted, meaning the Web API may not control them.
    /// Offering one as a transfer target produces a silent no-op, so they are filtered out.
    public var isControllable: Bool { id != nil && !isRestricted }

    /// True for the phone this app is running on, as best as can be told — Spotify does not
    /// say "this is you", only the device type and name.
    public var looksLikeThisPhone: Bool {
        type.caseInsensitiveCompare("Smartphone") == .orderedSame
    }
}

public struct SpotifyDevicesResponse: Decodable, Hashable, Sendable {
    public let devices: [SpotifyDevice]
}

/// What Spotify is doing right now, mapped onto the app's own vocabulary.
public struct SpotifyPlayback: Hashable, Sendable {
    public let isPlaying: Bool
    public let position: TimeInterval
    /// Nil for an advert, a local file Spotify cannot describe, or a podcast episode this
    /// build does not model — all of which are "something is playing but there is no track".
    public let item: NowPlayingItem?
    public let device: SpotifyDevice?

    public init(
        isPlaying: Bool,
        position: TimeInterval,
        item: NowPlayingItem?,
        device: SpotifyDevice?
    ) {
        self.isPlaying = isPlaying
        self.position = position
        self.item = item
        self.device = device
    }

    public var status: PlaybackStatus {
        isPlaying ? .playing : .paused
    }

    /// The state when `GET /v1/me/player` returns 204: Spotify is signed in but not playing
    /// anywhere. Not an error, and specifically not "unavailable".
    public static let idle = SpotifyPlayback(
        isPlaying: false,
        position: 0,
        item: nil,
        device: nil
    )
}

public enum SpotifyPlayerDecoder {
    /// Decodes `GET /v1/me/player`.
    ///
    /// - Parameter data: the body, or empty for a 204.
    public static func playback(from data: Data) throws -> SpotifyPlayback {
        // 204 No Content is the documented response when nothing is active. An empty body is
        // therefore success, not a parse failure — reading it as an error makes the tile
        // permanently claim Spotify is broken whenever music simply is not playing.
        guard !data.isEmpty else { return .idle }

        let response: PlayerResponse
        do {
            response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        } catch {
            throw SpotifyAPIError.malformedResponse("\(error)")
        }

        return SpotifyPlayback(
            isPlaying: response.is_playing ?? false,
            position: TimeInterval(response.progress_ms ?? 0) / 1000,
            item: response.item.map(nowPlaying),
            device: response.device
        )
    }

    public static func devices(from data: Data) throws -> [SpotifyDevice] {
        do {
            return try JSONDecoder().decode(SpotifyDevicesResponse.self, from: data).devices
        } catch {
            throw SpotifyAPIError.malformedResponse("\(error)")
        }
    }

    static func nowPlaying(_ track: TrackObject) -> NowPlayingItem {
        // A local file Spotify has no metadata for arrives with an empty artists array.
        // Joining that gives "", which renders as a blank second line rather than
        // collapsing the way a nil does.
        let artists = track.artists?.map(\.name).filter { !$0.isEmpty } ?? []

        return NowPlayingItem(
            title: track.name,
            artist: artists.isEmpty ? nil : artists.joined(separator: ", "),
            album: track.album?.name,
            duration: track.duration_ms.map { TimeInterval($0) / 1000 },
            artworkURL: track.album.flatMap { artworkURL(from: $0.images ?? []) },
            identifier: track.uri ?? track.id
        )
    }

    /// Spotify returns images largest first, typically 640/300/64 px. The largest is wasteful
    /// for a tile that is a couple of hundred points wide on a screen that is already fighting
    /// for bandwidth in a moving car, so the middle one is preferred.
    static func artworkURL(from images: [ImageObject]) -> URL? {
        let preferred = images.min {
            abs(($0.width ?? 0) - 300) < abs(($1.width ?? 0) - 300)
        }
        return (preferred ?? images.first).flatMap { URL(string: $0.url) }
    }

    // MARK: - Wire format
    //
    // Everything optional: Spotify omits fields for adverts, local files and podcast
    // episodes, and a struct of non-optionals fails to decode an otherwise usable response.

    struct PlayerResponse: Decodable {
        let device: SpotifyDevice?
        let is_playing: Bool?
        let progress_ms: Int?
        let item: TrackObject?
    }

    struct TrackObject: Decodable {
        let id: String?
        let uri: String?
        let name: String
        let duration_ms: Int?
        let artists: [ArtistObject]?
        let album: AlbumObject?
    }

    struct ArtistObject: Decodable {
        let name: String
    }

    struct AlbumObject: Decodable {
        let name: String?
        let images: [ImageObject]?
    }

    struct ImageObject: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }
}
