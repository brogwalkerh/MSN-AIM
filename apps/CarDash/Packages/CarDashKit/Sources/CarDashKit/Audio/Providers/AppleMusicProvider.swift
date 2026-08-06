import MediaPlayer
import Observation
import CarDashCore
import os

/// Plays the user's on-device music library.
///
/// Deliberately a *system-player* provider, not a file player, and the distinction is
/// the single most likely design mistake in this section. With iCloud Music Library
/// enabled — the default — `MPMediaItem.assetURL` is usually nil even for tracks the
/// user bought or ripped, so handing library items to `AVAudioPlayer` fails for most
/// people's libraries. `MPMusicPlayerController` plays them; it just does so in another
/// process, which is why `ProviderID.appleMusic.ownsAudioSession` is false.
///
/// No Apple Music subscription is required for any of this. Catalog browsing would be,
/// which is why there is none here — a paywall for something the user has not asked for
/// is worse than its absence.
@MainActor
@Observable
public final class AppleMusicProvider: PlaybackProvider {
    public struct Track: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let artist: String?
        public let album: String?
        public let duration: TimeInterval
    }

    public nonisolated var id: ProviderID { .appleMusic }
    public private(set) var tracks: [Track] = []
    public private(set) var authorization: MPMediaLibraryAuthorizationStatus = .notDetermined

    public var isAvailable: Bool { authorization == .authorized && !tracks.isEmpty }
    public var unavailableReason: String? {
        switch authorization {
        case .authorized:
            return tracks.isEmpty ? "No music found in your library." : nil
        case .denied, .restricted:
            return "Allow media library access in Settings to play your library."
        default:
            return "Tap to allow access to your music library."
        }
    }

    /// `applicationQueuePlayer`, not `systemMusicPlayer`: the app plays its own queue
    /// rather than hijacking whatever the Music app had lined up. Choosing a track here
    /// should not silently rewrite the user's Music app state.
    @ObservationIgnored private let player = MPMusicPlayerController.applicationQueuePlayer
    @ObservationIgnored private var sink: (@MainActor (ProviderEvent) -> Void)?
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "apple-music")

    public init() {
        authorization = MPMediaLibrary.authorizationStatus()
        if authorization == .authorized { loadLibrary() }
    }

    public func attach(_ sink: @escaping @MainActor (ProviderEvent) -> Void) {
        self.sink = sink
        startObserving()
    }

    public func requestAccess() async {
        let status = await MPMediaLibrary.requestAuthorization()
        authorization = status
        if status == .authorized { loadLibrary() }
    }

    private func loadLibrary() {
        let query = MPMediaQuery.songs()
        tracks = (query.items ?? []).prefix(2000).map { item in
            Track(
                id: String(item.persistentID),
                title: item.title ?? "Unknown",
                artist: item.artist,
                album: item.albumTitle,
                duration: item.playbackDuration
            )
        }
    }

    // MARK: - Playback

    public func play(_ track: Track) {
        guard let persistentID = UInt64(track.id) else { return }
        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaItemPropertyPersistentID
        )
        let query = MPMediaQuery(filterPredicates: [predicate])
        player.setQueue(with: query)
        player.play()
        publishNowPlaying()
    }

    public func perform(_ intent: PlaybackIntent) {
        switch intent {
        case .play:
            player.play()
        case .pause:
            player.pause()
        case .toggle:
            player.playbackState == .playing ? player.pause() : player.play()
        case .next:
            player.skipToNextItem()
        case .previous:
            player.currentPlaybackTime > 3
                ? player.skipToBeginning()
                : player.skipToPreviousItem()
        case .seek(let position):
            player.currentPlaybackTime = position
        case .stop, .switchTo:
            relinquish()
        }
    }

    public func relinquish() {
        player.pause()
        sink?(.status(id, .idle))
    }

    // MARK: - Observation

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        player.beginGeneratingPlaybackNotifications()

        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishState() }
        }

        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishNowPlaying() }
        }
    }

    private func publishState() {
        let status: PlaybackStatus
        switch player.playbackState {
        case .playing: status = .playing
        case .paused, .interrupted: status = .paused
        case .stopped: status = .idle
        default: status = .loading
        }
        sink?(.status(id, status))
        sink?(.position(id, player.currentPlaybackTime))
    }

    private func publishNowPlaying() {
        guard let item = player.nowPlayingItem else {
            sink?(.item(id, nil))
            return
        }
        sink?(.item(id, NowPlayingItem(
            title: item.title ?? "Unknown",
            artist: item.artist,
            album: item.albumTitle,
            duration: item.playbackDuration,
            identifier: String(item.persistentID)
        )))
        publishState()
    }
}
