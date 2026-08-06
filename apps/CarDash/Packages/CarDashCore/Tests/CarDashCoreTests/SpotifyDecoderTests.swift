import Foundation
import Testing
@testable import CarDashCore

@Suite("Spotify player state")
struct SpotifyPlayerDecoderTests {
    @Test("A playing track maps onto the app's own now-playing model")
    func playing() throws {
        let playback = try SpotifyPlayerDecoder.playback(from: try Fixture.data("spotify-player-playing"))

        #expect(playback.isPlaying)
        #expect(playback.status == .playing)
        // progress_ms is milliseconds; every other duration in the app is seconds.
        #expect(playback.position == 72.5)

        let item = try #require(playback.item)
        #expect(item.title == "Dreams")
        #expect(item.artist == "Fleetwood Mac, Stevie Nicks", "multiple artists are joined, not dropped")
        #expect(item.album == "Rumours")
        #expect(item.duration == 257.693)
        #expect(item.identifier == "spotify:track:0ofHAoxe9vBkTCp2UQIavz", "the URI, because that is what plays")

        let device = try #require(playback.device)
        #expect(device.name == "Kitchen speaker")
        #expect(device.isActive)
        #expect(device.isControllable)
        #expect(device.volumePercent == 54)
        #expect(!device.looksLikeThisPhone)
    }

    // 204 No Content is Spotify's documented answer when nothing is active anywhere. It is
    // the state a parked car is usually in, and reading it as a parse failure makes the
    // tile permanently claim Spotify is broken when it is simply idle.
    @Test("An empty body is idle, not a failure")
    func emptyBodyIsIdle() throws {
        let playback = try SpotifyPlayerDecoder.playback(from: Data())
        #expect(playback == .idle)
        #expect(!playback.isPlaying)
        #expect(playback.item == nil)
        #expect(playback.device == nil)
        #expect(playback.status == .paused, "idle Spotify is paused, never unavailable")
    }

    // Adverts, and podcast episodes this build does not model, arrive as is_playing with a
    // null item. Something *is* playing; there is just no track to describe.
    @Test("A null item is playback without a track")
    func advert() throws {
        let playback = try SpotifyPlayerDecoder.playback(from: try Fixture.data("spotify-player-advert"))
        #expect(playback.isPlaying)
        #expect(playback.item == nil)
        #expect(playback.position == 4)

        let device = try #require(playback.device)
        #expect(device.looksLikeThisPhone, "a Smartphone is how the API describes this handset")
    }

    // Local files Spotify has no catalogue entry for omit nearly everything. A struct of
    // non-optionals would fail to decode a response that is otherwise perfectly usable.
    @Test("A track with almost no metadata still decodes")
    func sparseTrack() throws {
        let playback = try SpotifyPlayerDecoder.playback(from: try Fixture.data("spotify-player-local-file"))
        #expect(!playback.isPlaying)
        #expect(playback.status == .paused)

        let item = try #require(playback.item)
        #expect(item.title == "track01")
        #expect(item.artist == nil, "an empty artists array must collapse, not render as a blank line")
        #expect(item.album == nil)
        #expect(item.duration == nil)
        #expect(item.artworkURL == nil)
        #expect(item.identifier == "spotify:local:::track01:212")

        let device = try #require(playback.device)
        #expect(!device.isControllable, "a restricted device with no id cannot be driven by the Web API")
    }

    // 640px art on a tile a couple of hundred points wide is bandwidth spent in a moving
    // car for nothing.
    @Test("Artwork prefers the ~300px image over the largest one")
    func artworkSizing() throws {
        let playback = try SpotifyPlayerDecoder.playback(from: try Fixture.data("spotify-player-playing"))
        let item = try #require(playback.item)
        #expect(item.artworkURL?.absoluteString == "https://i.scdn.co/image/aaa300")
    }

    @Test("Devices decode, and uncontrollable ones are identifiable")
    func devices() throws {
        let devices = try SpotifyPlayerDecoder.devices(from: try Fixture.data("spotify-devices"))
        #expect(devices.count == 4)

        let phone = try #require(devices.first { $0.name == "Brogan's iPhone" })
        #expect(phone.looksLikeThisPhone)
        #expect(phone.isControllable)
        #expect(!phone.isActive)

        let active = try #require(devices.first { $0.isActive })
        #expect(active.name == "Kitchen speaker")

        // Offering a restricted device as a transfer target produces a silent no-op, which
        // is indistinguishable from the app being broken.
        let tv = try #require(devices.first { $0.name == "Living room TV" })
        #expect(!tv.isControllable)

        let controllable = devices.filter { $0.isControllable }
        #expect(controllable.count == 3)
    }

    // Spotify's device object is the least uniform thing the API returns; cast targets and
    // desktop clients omit keys that speakers send. One absent `is_restricted` must not
    // fail the whole response.
    @Test("A device missing most of its fields still decodes")
    func sparseDevice() throws {
        let devices = try SpotifyPlayerDecoder.devices(from: try Fixture.data("spotify-devices"))
        let sparse = try #require(devices.first { $0.name == "Sparse cast target" })
        #expect(!sparse.isActive)
        #expect(!sparse.isRestricted)
        #expect(sparse.type == "Unknown")
        #expect(sparse.volumePercent == nil)
        #expect(sparse.isControllable, "it has an id, so it can be transferred to")
    }

    @Test(
        "Bodies that are not player responses are reported as malformed",
        arguments: ["[]", "{\"item\": 12}", "not json at all"]
    )
    func malformed(raw: String) {
        #expect(throws: SpotifyAPIError.self) {
            try SpotifyPlayerDecoder.playback(from: Data(raw.utf8))
        }
    }
}

@Suite("Spotify library")
struct SpotifyLibraryDecoderTests {
    @Test("Playlists decode with the URI needed to play them")
    func playlists() throws {
        let playlists = try SpotifyLibraryDecoder.playlists(from: try Fixture.data("spotify-playlists"))
        // Four in the fixture; the one with no id or uri is dropped because tapping it
        // could only ever do nothing.
        #expect(playlists.count == 3)
        let broken = playlists.first { $0.name == "Broken" }
        #expect(broken == nil)

        let driving = try #require(playlists.first)
        #expect(driving.id == "3cEYpjA9oz9GiPac4AsH4n")
        #expect(driving.name == "Driving")
        #expect(driving.owner == "Brogan")
        #expect(driving.trackCount == 137)
        #expect(driving.uri == "spotify:playlist:3cEYpjA9oz9GiPac4AsH4n")
        #expect(driving.artworkURL?.absoluteString == "https://i.scdn.co/image/pl300")

        // Missing fields must produce something displayable rather than dropping a
        // playlist the user can see in Spotify itself.
        let unnamed = try #require(playlists.first { $0.id == "1AVZz0mBuGbCEoNRQdYQju" })
        #expect(unnamed.name == "Untitled")
        #expect(unnamed.owner == nil)
        #expect(unnamed.trackCount == 0)
        #expect(unnamed.artworkURL == nil)

        let topHits = try #require(playlists.last)
        #expect(topHits.artworkURL?.absoluteString == "https://i.scdn.co/image/tk64", "the only size on offer")
    }

    @Test("Recently played decodes, deduplicated and newest first")
    func recentlyPlayed() throws {
        let recent = try SpotifyLibraryDecoder.recentlyPlayed(from: try Fixture.data("spotify-recently-played"))
        // Four entries: one repeat of Dreams and one null track, both dropped.
        #expect(recent.count == 2)

        let first = try #require(recent.first)
        #expect(first.item.title == "Dreams")
        #expect(first.uri == "spotify:track:0ofHAoxe9vBkTCp2UQIavz")
        // Spotify's played_at carries milliseconds, which the default ISO8601 options reject.
        #expect(abs(first.playedAt.timeIntervalSince1970 - 1_754_463_600.123) < 0.001)

        let second = try #require(recent.last)
        #expect(second.item.title == "Higher Ground")
        // And the same parser must still accept one without them.
        #expect(second.playedAt == Date(timeIntervalSince1970: 1_754_463_330))
        #expect(second.playedAt < first.playedAt, "Spotify returns history newest first")

        let identifiers = Set(recent.map(\.id))
        #expect(identifiers.count == recent.count, "identity is stable and unique per row")
    }

    @Test(
        "Library bodies that are not what was asked for are reported as malformed",
        arguments: ["{}", "[]", "{\"items\": 3}"]
    )
    func malformed(raw: String) {
        #expect(throws: SpotifyAPIError.self) {
            try SpotifyLibraryDecoder.playlists(from: Data(raw.utf8))
        }
        #expect(throws: SpotifyAPIError.self) {
            try SpotifyLibraryDecoder.recentlyPlayed(from: Data(raw.utf8))
        }
    }
}
