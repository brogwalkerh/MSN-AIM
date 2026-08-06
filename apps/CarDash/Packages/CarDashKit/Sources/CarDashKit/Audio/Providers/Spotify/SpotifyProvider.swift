import Foundation
import Observation
import SwiftUI
import CarDashCore
import os

/// Spotify, driven over the Web API.
///
/// The consequential thing about this provider is that it does not play anything. Audio
/// comes out of the Spotify app's own process, which is why `ProviderID.spotify
/// .ownsAudioSession` is false and why the state machine releases this app's
/// `AVAudioSession` before ever telling Spotify to play. Activating a `.playback` session
/// here would interrupt the very thing it is trying to start.
///
/// The second consequence is that there are no push updates: what Spotify is doing has to
/// be asked for. `SpotifyPollPolicy` decides how often, and the answer depends on whether
/// anyone can see it.
@MainActor
@Observable
public final class SpotifyProvider: PlaybackProvider {
    public nonisolated var id: ProviderID { .spotify }

    public private(set) var playlists: [SpotifyPlaylist] = []
    public private(set) var recent: [SpotifyRecentTrack] = []
    public private(set) var devices: [SpotifyDevice] = []
    public private(set) var isLoadingLibrary = false
    public private(set) var lastError: String?

    /// True when Spotify answered 404 NO_ACTIVE_DEVICE — the ordinary state of a phone
    /// that has just been put in a mount, not a fault. The tile offers a device to play on
    /// rather than an error.
    public private(set) var needsDevice = false

    public let auth: SpotifyAuthService

    public var isSignedIn: Bool { auth.isSignedIn }

    public var isAvailable: Bool {
        auth.state != .notConfigured
    }

    public var unavailableReason: String? {
        switch auth.state {
        case .notConfigured:
            return "Add a Spotify Client ID to Secrets.xcconfig to connect Spotify."
        case .signedOut, .authorizing:
            return "Connect your Spotify account."
        case .failed(let message):
            return message
        case .signedIn:
            return nil
        }
    }

    @ObservationIgnored private let client: SpotifyWebClient
    @ObservationIgnored private var sink: (@MainActor (ProviderEvent) -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var backoffUntil: Date?
    @ObservationIgnored private var isTileVisible = false
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var lastItem: NowPlayingItem?
    @ObservationIgnored private var lastStatus: PlaybackStatus = .idle
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "spotify")

    /// Optional rather than defaulted because a default argument expression is evaluated
    /// in a nonisolated context, where a main-actor type cannot be constructed.
    public init(auth: SpotifyAuthService? = nil) {
        let service = auth ?? SpotifyAuthService()
        self.auth = service
        self.client = SpotifyWebClient(auth: service)
    }

    public func attach(_ sink: @escaping @MainActor (ProviderEvent) -> Void) {
        self.sink = sink
        if auth.isSignedIn { startPolling() }
    }

    // MARK: - Account

    public func signIn() async {
        await auth.signIn()
        guard auth.isSignedIn else { return }
        await loadLibrary()
        startPolling()
    }

    public func signOut() {
        auth.signOut()
        stopPolling()
        playlists = []
        recent = []
        devices = []
        needsDevice = false
        lastError = nil
        sink?(.status(id, .idle))
        sink?(.item(id, nil))
    }

    // MARK: - Library

    public func loadLibrary() async {
        guard auth.isSignedIn, !isLoadingLibrary else { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        do {
            // Sequential rather than concurrent: two requests fired together against a
            // rate limit shared with polling buys a few hundred milliseconds on a screen
            // the driver is not looking at while parked.
            playlists = try await client.playlists()
            recent = try await client.recentlyPlayed()
            lastError = nil
        } catch {
            report(error)
        }
    }

    public func refreshDevices() async {
        guard auth.isSignedIn else { return }
        do {
            devices = try await client.devices()
        } catch {
            report(error)
        }
    }

    /// Starts a playlist. The `context_uri` form is what makes Spotify play the whole
    /// thing in its own order rather than a single track in isolation.
    public func play(_ playlist: SpotifyPlaylist) async {
        await command { try await self.client.play(contextURI: playlist.uri) }
    }

    public func play(_ track: SpotifyRecentTrack) async {
        await command { try await self.client.play(trackURIs: [track.uri]) }
    }

    /// Moves playback here, which is the answer to NO_ACTIVE_DEVICE.
    public func transfer(to device: SpotifyDevice) async {
        guard let deviceID = device.id else { return }
        await command { try await self.client.transfer(to: deviceID) }
    }

    /// The phone this app is running on, when Spotify can see it — the target for
    /// "Play on this iPhone".
    public var thisPhone: SpotifyDevice? {
        devices.first { $0.looksLikeThisPhone && $0.isControllable }
    }

    // MARK: - PlaybackProvider

    public func perform(_ intent: PlaybackIntent) {
        switch intent {
        case .play:
            Task { await command { try await self.client.play() } }
        case .pause:
            Task { await command { try await self.client.pause() } }
        case .toggle:
            let playing = lastStatus == .playing
            Task {
                await command {
                    if playing {
                        try await self.client.pause()
                    } else {
                        try await self.client.play()
                    }
                }
            }
        case .next:
            Task { await command { try await self.client.next() } }
        case .previous:
            Task { await command { try await self.client.previous() } }
        case .seek(let position):
            Task { await command { try await self.client.seek(to: position) } }
        case .stop, .switchTo:
            relinquish()
        }
    }

    /// Spotify keeps playing when another source takes over the tile — it is a separate
    /// app, and silently stopping someone's music because they tapped a different button
    /// would be surprising. Only the polling stops.
    public func relinquish() {
        stopPolling()
    }

    // MARK: - Polling

    /// Called by the tile appearing and disappearing, and by scene phase. Cadence is a
    /// pure function of these in `CarDashCore`.
    public func setVisibility(tileVisible: Bool? = nil, foreground: Bool? = nil) {
        if let tileVisible { isTileVisible = tileVisible }
        if let foreground { isForeground = foreground }
        guard auth.isSignedIn else { return }
        startPolling()
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()

                let conditions = SpotifyPollPolicy.Conditions(
                    isPlaying: self.lastStatus == .playing,
                    isTileVisible: self.isTileVisible,
                    isForeground: self.isForeground,
                    backoffUntil: self.backoffUntil
                )
                guard let interval = SpotifyPollPolicy.interval(for: conditions, now: Date()) else {
                    // Backgrounded. The task ends rather than idling; coming back to the
                    // foreground restarts it.
                    return
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        guard auth.isSignedIn else { return }
        do {
            let playback = try await client.playback()
            backoffUntil = nil
            needsDevice = false
            lastError = nil
            publish(playback)
        } catch {
            report(error)
        }
    }

    private func publish(_ playback: SpotifyPlayback) {
        // Only on change: the sink drives the state machine, and re-announcing the same
        // track every three seconds would republish now-playing info to the lock screen
        // just as often.
        if playback.item != lastItem {
            lastItem = playback.item
            sink?(.item(id, playback.item))
        }
        if playback.status != lastStatus {
            lastStatus = playback.status
            sink?(.status(id, playback.status))
        }
        sink?(.position(id, playback.position))
    }

    // MARK: - Errors

    private func command(_ body: @escaping () async throws -> Void) async {
        do {
            try await body()
            needsDevice = false
            lastError = nil
            // Spotify takes a moment to reflect a transport command, so the immediate
            // poll is deliberately delayed rather than fired at once.
            try? await Task.sleep(for: .milliseconds(400))
            await pollOnce()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Swift.Error) {
        guard let spotify = error as? SpotifyAPIError else {
            lastError = "Spotify is unreachable."
            return
        }

        switch spotify {
        case .noActiveDevice:
            // Not an error state. The tile switches to offering somewhere to play.
            needsDevice = true
            lastError = nil
            Task { await refreshDevices() }

        case .rateLimited(let retryAfter):
            backoffUntil = Date().addingTimeInterval(retryAfter)
            lastError = spotify.userFacingMessage

        case .unauthorized:
            // The client already retried once with a fresh token; a second 401 means the
            // grant is gone.
            lastError = spotify.userFacingMessage
            stopPolling()

        default:
            lastError = spotify.userFacingMessage
        }
    }
}
