import Foundation
import Testing
@testable import CarDashCore

@Suite("YouTube links")
struct YouTubeLinkTests {
    private let id = "dQw4w9WgXcQ"

    // A shared YouTube link arrives in about eight shapes. Getting this wrong means telling
    // someone "that isn't a YouTube link" about a link they copied from YouTube.
    @Test(
        "Every shape a shared link comes in",
        arguments: [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?v=dQw4w9WgXcQ",
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "https://www.youtube.com/live/dQw4w9WgXcQ",
            "https://www.youtube.com/v/dQw4w9WgXcQ",
            // Share sheets sometimes drop the scheme.
            "youtu.be/dQw4w9WgXcQ",
            "www.youtube.com/watch?v=dQw4w9WgXcQ",
            // And people paste with whitespace around it.
            "  https://youtu.be/dQw4w9WgXcQ  "
        ]
    )
    func shapes(link: String) {
        #expect(YouTubeLink.parse(link)?.id == id)
    }

    @Test("Extra parameters do not get in the way")
    func extraParameters() {
        #expect(YouTubeLink.parse("https://youtu.be/dQw4w9WgXcQ?si=abc123")?.id == id)
        #expect(YouTubeLink.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc&index=3")?.id == id)
        #expect(YouTubeLink.parse("https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ")?.id == id)
    }

    // Someone who copies just the id should not be told it is invalid.
    @Test("A bare id is accepted")
    func bareID() {
        #expect(YouTubeLink.parse(id)?.id == id)
        #expect(YouTubeLink.isValidID(id))
    }

    @Test(
        "Things that are not YouTube videos are refused",
        arguments: [
            "", "   ", "hello",
            "https://vimeo.com/123456",
            "https://example.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/",
            "https://www.youtube.com/results?search_query=cats",
            "https://www.youtube.com/watch?v=tooshort",
            "https://youtu.be/tooshort",
            // A channel, not a video.
            "https://www.youtube.com/@somechannel",
            // Right length, wrong alphabet.
            "https://youtu.be/abcdefghij!"
        ]
    )
    func rejected(link: String) {
        #expect(YouTubeLink.parse(link) == nil)
    }

    // A malicious-looking host that merely *contains* youtube.com must not be accepted.
    @Test("Lookalike hosts are not YouTube")
    func lookalikeHosts() {
        #expect(YouTubeLink.parse("https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ") == nil)
        #expect(YouTubeLink.parse("https://notyoutube.com/watch?v=dQw4w9WgXcQ") == nil)
        #expect(YouTubeLink.parse("https://myyoutu.be/dQw4w9WgXcQ") == nil)
    }

    @Test(
        "Timestamps are carried through, in both forms YouTube uses",
        arguments: [
            ("https://youtu.be/dQw4w9WgXcQ?t=42", 42),
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90", 90),
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=15", 15),
            ("https://youtu.be/dQw4w9WgXcQ?t=1m30s", 90),
            ("https://youtu.be/dQw4w9WgXcQ?t=1h2m3s", 3723),
            ("https://youtu.be/dQw4w9WgXcQ?t=90s", 90),
            ("https://youtu.be/dQw4w9WgXcQ?t=2m", 120),
            ("https://youtu.be/dQw4w9WgXcQ", 0),
            // Nonsense in the timestamp starts at the beginning rather than failing.
            ("https://youtu.be/dQw4w9WgXcQ?t=banana", 0)
        ]
    )
    func timestamps(link: String, expected: Int) {
        #expect(YouTubeLink.parse(link)?.startSeconds == expected)
    }

    @Test("A negative timestamp cannot produce a negative start")
    func negativeStart() {
        let video = YouTubeVideo(id: id, startSeconds: -30, addedAt: Date())
        #expect(video.startSeconds == 0)
    }

    @Test("Thumbnails come straight from YouTube's image host, with no API key")
    func thumbnail() throws {
        let video = try #require(YouTubeLink.video(from: "https://youtu.be/\(id)", now: Date()))
        let url = try #require(video.thumbnailURL)
        #expect(url.absoluteString == "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    @Test("A video with no title still displays as something")
    func displayTitle() {
        let untitled = YouTubeVideo(id: id, addedAt: Date())
        #expect(untitled.displayTitle == "YouTube video")
        #expect(YouTubeVideo(id: id, title: "   ", addedAt: Date()).displayTitle == "YouTube video")
        #expect(YouTubeVideo(id: id, title: "Never Gonna", addedAt: Date()).displayTitle == "Never Gonna")
    }
}

@Suite("YouTube recents")
struct YouTubeRecentsTests {
    private let now = Date(timeIntervalSince1970: 1_754_463_600)

    private func video(_ id: String, title: String? = nil) -> YouTubeVideo {
        YouTubeVideo(id: id, title: title, addedAt: now)
    }

    @Test("Most recent first")
    func ordering() {
        let list = YouTubeRecents()
            .adding(video("aaaaaaaaaaa"))
            .adding(video("bbbbbbbbbbb"))
        #expect(list.videos.map(\.id) == ["bbbbbbbbbbb", "aaaaaaaaaaa"])
    }

    // A list that grows a duplicate on every replay is worse to live with than one that
    // reorders itself.
    @Test("Replaying something moves it to the front rather than duplicating it")
    func replayMoves() {
        let list = YouTubeRecents()
            .adding(video("aaaaaaaaaaa"))
            .adding(video("bbbbbbbbbbb"))
            .adding(video("aaaaaaaaaaa"))

        #expect(list.videos.count == 2)
        #expect(list.videos.first?.id == "aaaaaaaaaaa")
    }

    // The title only arrives once the player has loaded the video, so replaying from a link
    // must not wipe the name learned last time.
    @Test("A title learned earlier survives a replay from a bare link")
    func titleSurvivesReplay() {
        let list = YouTubeRecents()
            .adding(video("aaaaaaaaaaa"))
            .naming("aaaaaaaaaaa", "Something Good")
            .adding(video("aaaaaaaaaaa"))

        #expect(list.videos.first?.title == "Something Good")
    }

    @Test("Naming an entry fills in the title")
    func naming() {
        let list = YouTubeRecents().adding(video("aaaaaaaaaaa")).naming("aaaaaaaaaaa", "  Titled  ")
        #expect(list.videos.first?.title == "Titled")

        // An empty title from the player is not an instruction to erase the one we have.
        let unchanged = list.naming("aaaaaaaaaaa", "   ")
        #expect(unchanged.videos.first?.title == "Titled")
    }

    @Test("The list is capped")
    func capacity() {
        var list = YouTubeRecents()
        for index in 0..<(YouTubeRecents.capacity + 5) {
            list = list.adding(video(String(format: "%011d", index)))
        }
        #expect(list.videos.count == YouTubeRecents.capacity)
        #expect(list.videos.first?.id == String(format: "%011d", YouTubeRecents.capacity + 4))
    }

    @Test("Removing works and round trips survive JSON")
    func removingAndCodable() throws {
        let list = YouTubeRecents().adding(video("aaaaaaaaaaa")).adding(video("bbbbbbbbbbb"))
        #expect(list.removing("aaaaaaaaaaa").videos.map(\.id) == ["bbbbbbbbbbb"])
        #expect(list.removing("zzzzzzzzzzz").videos.count == 2)

        let decoded = try JSONDecoder().decode(
            YouTubeRecents.self,
            from: try JSONEncoder().encode(list)
        )
        #expect(decoded == list)
    }
}

@Suite("YouTube player bridge")
struct YouTubePlayerStateTests {
    // Buffering read as paused makes the transport bar flip to "play" every time the network
    // stutters; `cued` read as idle throws away metadata that was only just published.
    @Test(
        "Player states map to something the transport bar can show",
        arguments: [
            (YouTubePlayerState.playing, PlaybackStatus.playing),
            (.paused, .paused),
            (.buffering, .loading),
            (.unstarted, .paused),
            (.cued, .paused),
            (.ended, .idle)
        ]
    )
    func mapping(state: YouTubePlayerState, expected: PlaybackStatus) {
        #expect(state.playbackStatus == expected)
    }

    @Test("Only ending counts as finished")
    func finished() {
        for state in YouTubePlayerState.allCases {
            #expect(state.isFinished == (state == .ended))
        }
    }

    @Test("Unknown state codes are refused rather than guessed")
    func unknownCodes() {
        #expect(YouTubePlayerState(code: 1) == .playing)
        #expect(YouTubePlayerState(code: 4) == nil)
        #expect(YouTubePlayerState(code: 99) == nil)
    }

    @Test("Well-formed bridge messages decode")
    func decodesEvents() {
        #expect(YouTubePlayerEvent.decode(["kind": "state", "value": 1]) == .state(.playing))
        #expect(YouTubePlayerEvent.decode(["kind": "duration", "value": 212.0]) == .duration(212))
        #expect(YouTubePlayerEvent.decode(["kind": "position", "value": 12.5]) == .position(12.5))
        #expect(YouTubePlayerEvent.decode(["kind": "title", "value": "A Song"]) == .title("A Song"))
    }

    // The bridge is the boundary with JavaScript, so anything can arrive. An unrecognised
    // message has to be a nil rather than a crash or a wrong state.
    // Not parameterised, because `[String: Any]` is not Sendable and so cannot be a test
    // argument — which is itself a fair hint about what this boundary is like.
    @Test("Malformed bridge messages are refused")
    func malformed() {
        let payloads: [[String: Any]] = [
            [:],
            ["kind": "state"],
            ["kind": "state", "value": "playing"],
            ["kind": "state", "value": 42],
            ["kind": "duration", "value": Double.nan],
            ["kind": "duration", "value": -1.0],
            ["kind": "position", "value": Double.infinity],
            ["kind": "title", "value": "  "],
            ["kind": "nonsense", "value": 1]
        ]
        for payload in payloads {
            let decoded = YouTubePlayerEvent.decode(payload)
            #expect(decoded == nil, "\(payload) should not decode")
        }
    }

    // These call for different responses: a video the owner blocked from embedding can only be
    // watched in YouTube itself, and "playback failed" would leave someone retrying forever.
    @Test(
        "Error codes are distinguished, because the answers differ",
        arguments: [
            (2, false), (5, true), (100, false), (101, true), (150, true), (999, false)
        ]
    )
    func errors(code: Int, needsApp: Bool) {
        #expect(!YouTubeError.message(for: code).isEmpty)
        #expect(YouTubeError.needsTheYouTubeApp(code) == needsApp)
    }

    @Test("An error message names the actual problem")
    func errorMessages() {
        #expect(YouTubeError.message(for: 100).contains("removed"))
        #expect(YouTubeError.message(for: 101).lowercased().contains("owner"))
        let event = YouTubePlayerEvent.decode(["kind": "error", "value": 150])
        #expect(event == .failed(code: 150, message: YouTubeError.message(for: 150)))
    }
}
