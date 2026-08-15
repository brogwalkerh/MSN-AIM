import Foundation
import Observation
import CarDashCore
import os

/// YouTube, played through the embedded IFrame player.
///
/// The only provider whose audio genuinely comes out of this app's process — Spotify and the
/// Music app play in their own, and local files go through `AVAudioPlayer`. So
/// `ProviderID.youtube.ownsAudioSession` is true and the state machine activates the session
/// before telling this to play.
///
/// The awkward consequence, and the reason this tile is honest about being a parked-car tile:
/// the app holds the `audio` background mode for its own local files, so a YouTube video
/// *would* keep playing with the screen off. YouTube's terms do not permit that, so this
/// deliberately pauses when the app leaves the foreground. It is the one place in this project
/// where the app does less than it technically could.
@MainActor
@Observable
public final class YouTubeProvider: PlaybackProvider {
    public nonisolated var id: ProviderID { .youtube }

    public private(set) var recents = YouTubeRecents()
    public private(set) var current: YouTubeVideo?
    public private(set) var lastError: String?
    /// Set when a video can only be watched in the YouTube app itself.
    public private(set) var needsTheApp = false

    /// Always usable — there is nothing to sign into and nothing to install.
    public var isAvailable: Bool { true }

    /// The web view the tile displays. Owned here rather than by the view so that audio and
    /// position survive the tile being re-laid-out, or scrolled off and back.
    let player = YouTubeWebPlayer()

    @ObservationIgnored private var sink: (@MainActor (ProviderEvent) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var duration: TimeInterval?
    @ObservationIgnored private var wasPlayingBeforeBackground = false
    @ObservationIgnored private static let key = "cardash.youtube.recents"
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "youtube")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        player.onEvent = { [weak self] event in self?.handle(event) }
    }

    public func attach(_ sink: @escaping @MainActor (ProviderEvent) -> Void) {
        self.sink = sink
    }

    // MARK: - Choosing something to play

    /// Accepts whatever was pasted — a link in any of its shapes, or a bare id.
    ///
    /// - Returns: false when it was not a YouTube video, so the caller can say so.
    @discardableResult
    public func add(fromPastedText text: String) -> Bool {
        guard let video = YouTubeLink.video(from: text, now: Date()) else {
            lastError = "That doesn't look like a YouTube link."
            return false
        }
        lastError = nil
        recents = recents.adding(video)
        save()
        play(video)
        return true
    }

    public func play(_ video: YouTubeVideo) {
        lastError = nil
        needsTheApp = false
        duration = nil
        current = video
        recents = recents.adding(video)
        save()

        player.load(video)
        sink?(.item(id, nowPlayingItem(for: video)))
        sink?(.status(id, .loading))
    }

    public func remove(_ id: String) {
        recents = recents.removing(id)
        save()
    }

    /// The URL to hand to the YouTube app when a video refuses to embed.
    public var currentVideoURL: URL? {
        current.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.id)") }
    }

    // MARK: - PlaybackProvider

    public func perform(_ intent: PlaybackIntent) {
        switch intent {
        case .play:
            player.play()
        case .pause:
            player.pause()
        case .toggle:
            // The web view is the source of truth for whether it is playing, and asking it
            // costs a round trip — so this follows the last state the bridge reported.
            isPlaying ? player.pause() : player.play()
        case .next:
            step(by: 1)
        case .previous:
            // Matches every other player: part-way in, "previous" restarts the track.
            if position > 3 { player.seek(to: 0) } else { step(by: -1) }
        case .seek(let target):
            player.seek(to: target)
        case .stop, .switchTo:
            relinquish()
        }
    }

    /// Another source took over. The page is torn down rather than paused, because a paused
    /// YouTube player keeps a media session alive and would sit in the lock-screen controls
    /// competing with whatever the user just switched to.
    public func relinquish() {
        player.stop()
        current = nil
        duration = nil
        isPlaying = false
        sink?(.status(id, .idle))
        sink?(.item(id, nil))
    }

    // MARK: - Foreground only

    /// Called from the tile as the scene phase changes.
    ///
    /// Pausing on background is a deliberate restriction rather than a technical limit: the app
    /// has the background audio entitlement and could keep playing. YouTube's terms say not to.
    public func setForeground(_ isForeground: Bool) {
        if isForeground {
            if wasPlayingBeforeBackground {
                wasPlayingBeforeBackground = false
                player.play()
            }
        } else {
            wasPlayingBeforeBackground = isPlaying
            player.pause()
        }
    }

    // MARK: - Bridge events

    @ObservationIgnored private var isPlaying = false
    @ObservationIgnored private var position: TimeInterval = 0

    private func handle(_ event: YouTubePlayerEvent) {
        switch event {
        case .state(let state):
            isPlaying = state == .playing
            sink?(.status(id, state.playbackStatus))
            // Advancing on its own is what makes a queue of recents behave like a playlist
            // rather than a list that stops after one video.
            if state.isFinished { step(by: 1) }

        case .position(let seconds):
            position = seconds
            sink?(.position(id, seconds))

        case .duration(let seconds):
            duration = seconds
            if let current { sink?(.item(id, nowPlayingItem(for: current))) }

        case .title(let title):
            guard let current else { return }
            recents = recents.naming(current.id, title)
            self.current?.title = title
            save()
            sink?(.item(id, nowPlayingItem(for: current, title: title)))

        case .failed(let code, let message):
            lastError = message
            needsTheApp = YouTubeError.needsTheYouTubeApp(code)
            isPlaying = false
            sink?(.status(id, .paused))
            Self.log.error("player error \(code): \(message)")
        }
    }

    private func nowPlayingItem(for video: YouTubeVideo, title: String? = nil) -> NowPlayingItem {
        NowPlayingItem(
            title: title ?? video.displayTitle,
            artist: "YouTube",
            album: nil,
            duration: duration,
            artworkURL: video.thumbnailURL,
            identifier: video.id
        )
    }

    /// Moves through the recents list, which is the only ordering this tile has.
    private func step(by offset: Int) {
        guard let current,
              let index = recents.videos.firstIndex(where: { $0.id == current.id })
        else { return }

        let next = index + offset
        guard recents.videos.indices.contains(next) else {
            // Ran off the end of the list. Stopping is better than wrapping round to the
            // beginning and replaying something from last week.
            player.pause()
            sink?(.status(id, .paused))
            return
        }
        play(recents.videos[next])
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            recents = try JSONDecoder().decode(YouTubeRecents.self, from: data)
        } catch {
            Self.log.error("could not read recents: \(error)")
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(recents), forKey: Self.key)
        } catch {
            Self.log.error("could not save recents: \(error)")
        }
    }
}
