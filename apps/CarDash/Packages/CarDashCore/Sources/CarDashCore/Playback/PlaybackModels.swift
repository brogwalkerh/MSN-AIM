import Foundation

/// Which music source is driving playback.
public enum ProviderID: String, Codable, Sendable, Hashable, CaseIterable {
    case spotify
    case appleMusic
    case localFiles
    case youtube

    /// Whether audio comes out of *this* app's process.
    ///
    /// The distinction the whole audio design turns on. Spotify and the Music app play
    /// in their own processes, so this app's `AVAudioSession` does not govern them —
    /// activating a `.playback` session while they are playing interrupts them. Only the
    /// two providers below own the session.
    public var ownsAudioSession: Bool {
        switch self {
        case .localFiles, .youtube: return true
        case .spotify, .appleMusic: return false
        }
    }

    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .localFiles: return "My Files"
        case .youtube: return "YouTube"
        }
    }
}

public enum PlaybackStatus: String, Sendable, Hashable, Codable {
    case idle
    case loading
    case playing
    case paused
    /// The provider is unreachable — Spotify not installed, or its app was killed.
    case unavailable
}

public struct NowPlayingItem: Hashable, Sendable, Codable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let artworkURL: URL?
    /// Provider-specific handle, opaque here.
    public let identifier: String?

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        identifier: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.identifier = identifier
    }
}

/// What the user asked for.
public enum PlaybackIntent: Hashable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek(TimeInterval)
    case switchTo(ProviderID)
    case stop
}

/// What a provider told us.
public enum ProviderEvent: Hashable, Sendable {
    case status(ProviderID, PlaybackStatus)
    case item(ProviderID, NowPlayingItem?)
    case position(ProviderID, TimeInterval)
    case failed(ProviderID, String)
    case lostConnection(ProviderID)
    case regainedConnection(ProviderID)
    /// The system interrupted playback — a call, or another app taking the session.
    case interrupted
    /// The interruption ended and the system says it is safe to resume.
    case interruptionEndedResumable
    /// Headphones unplugged, Bluetooth dropped.
    case outputDeviceLost
}

/// What the coordinator must actually do.
public enum PlaybackCommand: Hashable, Sendable {
    case activateSession
    case deactivateSession
    case tell(ProviderID, PlaybackIntent)
    case publishNowPlaying(NowPlayingItem?)
    case clearNowPlaying
}

public struct UnifiedPlaybackState: Hashable, Sendable {
    public var activeProvider: ProviderID?
    public var status: PlaybackStatus
    public var item: NowPlayingItem?
    public var position: TimeInterval
    /// True while playback is paused because the system interrupted it, so it can be
    /// resumed automatically — as opposed to the user pausing, which must not be undone.
    public var pausedByInterruption: Bool

    public init(
        activeProvider: ProviderID? = nil,
        status: PlaybackStatus = .idle,
        item: NowPlayingItem? = nil,
        position: TimeInterval = 0,
        pausedByInterruption: Bool = false
    ) {
        self.activeProvider = activeProvider
        self.status = status
        self.item = item
        self.position = position
        self.pausedByInterruption = pausedByInterruption
    }

    public var isPlaying: Bool { status == .playing }
}
