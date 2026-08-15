import Foundation

/// The IFrame player's own state codes, and what they mean to the rest of the app.
///
/// YouTube's embedded player reports state as a bare integer over a JavaScript bridge. Mapping
/// it here rather than in the web view keeps the one part that can be got wrong — buffering
/// being read as stopped, `cued` being read as playing — under test on Linux.
public enum YouTubePlayerState: Int, Codable, Hashable, Sendable, CaseIterable {
    case unstarted = -1
    case ended = 0
    case playing = 1
    case paused = 2
    case buffering = 3
    case cued = 5

    public init?(code: Int) {
        self.init(rawValue: code)
    }

    public var playbackStatus: PlaybackStatus {
        switch self {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .buffering:
            // Loading rather than paused: a transport bar that flips to "play" every time the
            // network stutters is worse than one that says it is working.
            return .loading
        case .unstarted, .cued:
            // A video is loaded and waiting. Idle would clear the now-playing metadata that was
            // only just published.
            return .paused
        case .ended:
            return .idle
        }
    }

    /// Whether the video finished on its own, which is the cue to advance.
    public var isFinished: Bool { self == .ended }
}

/// What the web view reports back to the app.
///
/// A single tagged message rather than several, so the bridge has exactly one shape to get
/// right and an unrecognised message is a decode failure rather than a silent no-op.
public enum YouTubePlayerEvent: Hashable, Sendable {
    case state(YouTubePlayerState)
    case duration(TimeInterval)
    case position(TimeInterval)
    case title(String)
    /// The IFrame API's `onError` codes: 2 bad id, 5 HTML5 error, 100 removed or private,
    /// 101 and 150 both mean the owner disallowed embedding.
    case failed(code: Int, message: String)

    public static func decode(_ payload: [String: Any]) -> YouTubePlayerEvent? {
        guard let kind = payload["kind"] as? String else { return nil }

        switch kind {
        case "state":
            guard let code = payload["value"] as? Int,
                  let state = YouTubePlayerState(code: code) else { return nil }
            return .state(state)

        case "duration":
            guard let value = payload["value"] as? Double, value.isFinite, value >= 0 else { return nil }
            return .duration(value)

        case "position":
            guard let value = payload["value"] as? Double, value.isFinite, value >= 0 else { return nil }
            return .position(value)

        case "title":
            guard let value = payload["value"] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .title(value)

        case "error":
            let code = payload["value"] as? Int ?? -1
            return .failed(code: code, message: YouTubeError.message(for: code))

        default:
            return nil
        }
    }
}

public enum YouTubeError {
    /// Says which of the failures it is, because they call for different responses: a video the
    /// owner has blocked from embedding can only be watched in YouTube itself, and telling the
    /// user "playback failed" would leave them retrying something that cannot work.
    public static func message(for code: Int) -> String {
        switch code {
        case 2:
            return "That video link isn't valid."
        case 5:
            return "This video can't play in an embedded player."
        case 100:
            return "That video was removed or is private."
        case 101, 150:
            return "The owner doesn't allow this video to play outside YouTube."
        default:
            return "That video couldn't be played."
        }
    }

    /// Whether opening the video in the YouTube app is the only way to watch it.
    public static func needsTheYouTubeApp(_ code: Int) -> Bool {
        code == 101 || code == 150 || code == 5
    }
}
