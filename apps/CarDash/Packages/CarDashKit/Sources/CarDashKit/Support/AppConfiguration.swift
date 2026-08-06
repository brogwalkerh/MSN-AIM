import Foundation

/// Build-time configuration read from the bundle.
///
/// The Spotify client ID arrives via `Base.xcconfig`, which is empty in the repository and
/// overridden by an untracked `Secrets.xcconfig`. That means a fresh clone builds and runs
/// with no Spotify credentials at all, and *that* has to be an ordinary supported state
/// rather than something that crashes or shows a broken tile — anyone building this
/// without a developer.spotify.com account should get a working dashboard.
public enum AppConfiguration {
    /// Nil when no client ID was configured, or when the build setting failed to expand.
    public static var spotifyClientID: String? {
        value(for: "SpotifyClientID")
    }

    public static var isSpotifyConfigured: Bool {
        spotifyClientID != nil
    }

    static func value(for key: String, in bundle: Bundle = .main) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // An unexpanded `$(SPOTIFY_CLIENT_ID)` reaching the authorization endpoint gets a
        // generic invalid_client back, which points at the dashboard rather than at the
        // build settings where the fault actually is.
        guard !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
