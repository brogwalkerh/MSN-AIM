import Foundation
import MediaPlayer
import Observation
import CarDashCore
import os

/// The imperative shell around `PlaybackStateMachine`.
///
/// Holds the providers, feeds their events to the machine, and executes the commands it
/// emits. All the decisions live in Core, where they are tested; this file does what it
/// is told.
@MainActor
@Observable
public final class AudioCoordinator {
    public private(set) var state = UnifiedPlaybackState()

    public let localFiles = LocalFilesProvider()
    public let appleMusic = AppleMusicProvider()
    public let spotify = SpotifyProvider()
    public let youtube = YouTubeProvider()

    @ObservationIgnored private var machine = PlaybackStateMachine()
    @ObservationIgnored private let session = AudioSessionController()
    @ObservationIgnored private var providers: [ProviderID: any PlaybackProvider] = [:]
    @ObservationIgnored private var remoteCommandsWired = false
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "audio")

    public init() {
        providers = [
            .localFiles: localFiles,
            .appleMusic: appleMusic,
            .spotify: spotify,
            .youtube: youtube
        ]

        session.configure()
        session.onEvent = { [weak self] event in self?.apply(event) }

        for provider in providers.values {
            provider.attach { [weak self] event in self?.apply(event) }
        }
        wireRemoteCommands()
    }

    public func provider(_ id: ProviderID) -> (any PlaybackProvider)? {
        providers[id]
    }

    public var availableProviders: [ProviderID] {
        ProviderID.allCases.filter { providers[$0]?.isAvailable == true }
    }

    // MARK: - Driving

    public func send(_ intent: PlaybackIntent) {
        if case .switchTo(let next) = intent, let current = state.activeProvider, current != next {
            providers[current]?.relinquish()
        }
        run(machine.handle(intent))
    }

    private func apply(_ event: ProviderEvent) {
        run(machine.handle(event))
    }

    private func run(_ commands: [PlaybackCommand]) {
        for command in commands {
            switch command {
            case .activateSession:
                session.activate()
            case .deactivateSession:
                session.deactivate()
            case .tell(let providerID, let intent):
                providers[providerID]?.perform(intent)
            case .publishNowPlaying(let item):
                publishNowPlaying(item)
            case .clearNowPlaying:
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
        }
        state = machine.state
    }

    // MARK: - Lock screen and steering wheel

    private func publishNowPlaying(_ item: NowPlayingItem?) {
        guard let item else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0
        ]
        if let artist = item.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = item.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = item.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func wireRemoteCommands() {
        guard !remoteCommandsWired else { return }
        remoteCommandsWired = true

        let centre = MPRemoteCommandCenter.shared()

        centre.playCommand.addTarget { [weak self] _ in
            self?.send(.play)
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            self?.send(.pause)
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.send(.toggle)
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            self?.send(.next)
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            self?.send(.previous)
            return .success
        }
        centre.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.send(.seek(event.positionTime))
            return .success
        }

        // Commands the app cannot service are disabled explicitly, so the system hides
        // them instead of showing a steering-wheel button that does nothing.
        centre.skipForwardCommand.isEnabled = false
        centre.skipBackwardCommand.isEnabled = false
        centre.seekForwardCommand.isEnabled = false
        centre.seekBackwardCommand.isEnabled = false
        centre.ratingCommand.isEnabled = false
        centre.likeCommand.isEnabled = false
        centre.dislikeCommand.isEnabled = false
    }
}
