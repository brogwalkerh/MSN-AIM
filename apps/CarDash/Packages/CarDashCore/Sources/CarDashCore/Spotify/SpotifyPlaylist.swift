import Foundation

/// A playlist, flattened to what a tile in a car actually shows.
public struct SpotifyPlaylist: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let owner: String?
    public let trackCount: Int
    public let artworkURL: URL?
    /// `spotify:playlist:…` — what `PUT /me/player/play` wants as `context_uri`.
    public let uri: String

    public init(
        id: String,
        name: String,
        owner: String?,
        trackCount: Int,
        artworkURL: URL?,
        uri: String
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.trackCount = trackCount
        self.artworkURL = artworkURL
        self.uri = uri
    }
}

/// A track that was played recently, with the URI needed to play it again.
public struct SpotifyRecentTrack: Hashable, Sendable, Identifiable {
    public var id: String { "\(uri)-\(playedAt.timeIntervalSince1970)" }
    public let item: NowPlayingItem
    public let uri: String
    public let playedAt: Date

    public init(item: NowPlayingItem, uri: String, playedAt: Date) {
        self.item = item
        self.uri = uri
        self.playedAt = playedAt
    }
}

public enum SpotifyLibraryDecoder {
    public static func playlists(from data: Data) throws -> [SpotifyPlaylist] {
        do {
            let response = try JSONDecoder().decode(PlaylistsResponse.self, from: data)
            return response.items.compactMap { item in
                // A playlist with no id or uri cannot be played, so it is dropped rather than
                // listed as something that will do nothing when tapped.
                guard let id = item.id, let uri = item.uri else { return nil }
                return SpotifyPlaylist(
                    id: id,
                    name: item.name ?? "Untitled",
                    owner: item.owner?.display_name,
                    trackCount: item.tracks?.total ?? 0,
                    artworkURL: SpotifyPlayerDecoder.artworkURL(from: item.images ?? []),
                    uri: uri
                )
            }
        } catch {
            throw SpotifyAPIError.malformedResponse("\(error)")
        }
    }

    public static func recentlyPlayed(from data: Data) throws -> [SpotifyRecentTrack] {
        do {
            let response = try JSONDecoder().decode(RecentlyPlayedResponse.self, from: data)
            let formatter = ISO8601DateFormatter()
            // Spotify's played_at carries milliseconds; the default options reject that.
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()

            var seen = Set<String>()
            return response.items.compactMap { entry in
                guard let track = entry.track, let uri = track.uri else { return nil }
                // The same track appears repeatedly in a listening history; showing it once
                // is what makes the list useful at a glance.
                guard seen.insert(uri).inserted else { return nil }

                let played = entry.played_at.flatMap {
                    formatter.date(from: $0) ?? plain.date(from: $0)
                } ?? Date(timeIntervalSince1970: 0)

                return SpotifyRecentTrack(
                    item: SpotifyPlayerDecoder.nowPlaying(track),
                    uri: uri,
                    playedAt: played
                )
            }
        } catch {
            throw SpotifyAPIError.malformedResponse("\(error)")
        }
    }

    // MARK: - Wire format

    struct PlaylistsResponse: Decodable {
        let items: [PlaylistObject]
    }

    struct PlaylistObject: Decodable {
        let id: String?
        let uri: String?
        let name: String?
        let images: [SpotifyPlayerDecoder.ImageObject]?
        let owner: OwnerObject?
        let tracks: TracksObject?
    }

    struct OwnerObject: Decodable {
        let display_name: String?
    }

    struct TracksObject: Decodable {
        let total: Int?
    }

    struct RecentlyPlayedResponse: Decodable {
        let items: [RecentItem]
    }

    struct RecentItem: Decodable {
        let track: SpotifyPlayerDecoder.TrackObject?
        let played_at: String?
    }
}
