import Foundation

/// Decides what happens when a user presses play, a provider reports something, or the
/// system interrupts.
///
/// Pure on purpose. Audio handoff between four providers — two of which play in another
/// process entirely — is the part of this app most likely to be subtly wrong, and the
/// only way to exercise it without a phone, a Spotify subscription and an incoming
/// phone call is to make it a function.
public struct PlaybackStateMachine: Sendable {
    public private(set) var state: UnifiedPlaybackState

    public init(state: UnifiedPlaybackState = UnifiedPlaybackState()) {
        self.state = state
    }

    // MARK: - Intents

    public mutating func handle(_ intent: PlaybackIntent) -> [PlaybackCommand] {
        switch intent {
        case .switchTo(let provider):
            return switchTo(provider)

        case .play:
            return play()

        case .pause:
            guard let active = state.activeProvider else { return [] }
            state.status = .paused
            // Deliberate: a user pause is not resumable by an interruption ending.
            // Otherwise hanging up a call restarts music the driver had silenced.
            state.pausedByInterruption = false
            return [.tell(active, .pause)]

        case .toggle:
            return state.isPlaying ? handle(.pause) : handle(.play)

        case .next, .previous:
            guard let active = state.activeProvider else { return [] }
            return [.tell(active, intent)]

        case .seek(let position):
            guard let active = state.activeProvider else { return [] }
            state.position = position
            return [.tell(active, .seek(position))]

        case .stop:
            guard let active = state.activeProvider else { return [] }
            state = UnifiedPlaybackState()
            return [.tell(active, .pause), .deactivateSession, .clearNowPlaying]
        }
    }

    private mutating func switchTo(_ provider: ProviderID) -> [PlaybackCommand] {
        guard provider != state.activeProvider else { return [] }

        var commands: [PlaybackCommand] = []
        if let current = state.activeProvider, state.isPlaying {
            commands.append(.tell(current, .pause))
        }

        state.activeProvider = provider
        state.item = nil
        state.position = 0
        state.status = .idle
        state.pausedByInterruption = false

        // Hand the session back before the new provider is asked for anything. Choosing
        // a source does not start playback — that is a second, explicit intent.
        if !provider.ownsAudioSession {
            commands.append(.deactivateSession)
            commands.append(.clearNowPlaying)
        }
        return commands
    }

    private mutating func play() -> [PlaybackCommand] {
        guard let active = state.activeProvider else { return [] }
        state.pausedByInterruption = false
        state.status = .loading

        if active.ownsAudioSession {
            // We are the ones making noise, so we take the session and own the lock
            // screen with it.
            return [.activateSession, .tell(active, .play), .publishNowPlaying(state.item)]
        }

        // Spotify and the Music app play in their own process. Releasing the session
        // *before* telling them to play is what makes it work: with it still active,
        // they start and are immediately cut off. Clearing now-playing avoids fighting
        // them for the lock screen, which they legitimately own while they are the
        // source.
        return [.deactivateSession, .clearNowPlaying, .tell(active, .play)]
    }

    // MARK: - Events

    public mutating func handle(_ event: ProviderEvent) -> [PlaybackCommand] {
        switch event {
        case .status(let provider, let status):
            // A provider that is not the active one has no business changing what is on
            // screen. Spotify continuing to report state after the user switched to
            // local files would otherwise redraw the transport bar with the wrong track.
            guard provider == state.activeProvider else { return [] }
            state.status = status
            if status == .playing, provider.ownsAudioSession {
                return [.publishNowPlaying(state.item)]
            }
            return []

        case .item(let provider, let item):
            guard provider == state.activeProvider else { return [] }
            state.item = item
            return provider.ownsAudioSession ? [.publishNowPlaying(item)] : []

        case .position(let provider, let position):
            guard provider == state.activeProvider else { return [] }
            state.position = position
            return []

        case .failed(let provider, _):
            guard provider == state.activeProvider else { return [] }
            state.status = .unavailable
            return []

        case .lostConnection(let provider):
            guard provider == state.activeProvider else { return [] }
            state.status = .unavailable
            return []

        case .regainedConnection(let provider):
            guard provider == state.activeProvider else { return [] }
            // Reconnected, but not assumed to be playing — the provider will report its
            // real state next.
            if state.status == .unavailable { state.status = .paused }
            return []

        case .interrupted:
            guard let active = state.activeProvider, state.isPlaying else {
                // Nothing was playing, so there is nothing to resume afterwards. Marking
                // it resumable here is how a phone call ends up starting music that was
                // never on.
                return []
            }
            state.status = .paused
            state.pausedByInterruption = true
            return [.tell(active, .pause)]

        case .interruptionEndedResumable:
            guard let active = state.activeProvider, state.pausedByInterruption else {
                return []
            }
            state.pausedByInterruption = false
            state.status = .loading
            return [.tell(active, .play)]

        case .outputDeviceLost:
            guard let active = state.activeProvider, state.isPlaying else { return [] }
            state.status = .paused
            // Not resumable. Unplugging headphones or leaving Bluetooth range means the
            // audio should stay off until asked for again — blasting it out of the
            // phone speaker is the behaviour everyone hates.
            state.pausedByInterruption = false
            return [.tell(active, .pause)]
        }
    }
}
