import Foundation

/// URL and form-body construction for Spotify's authorization-code-with-PKCE flow.
///
/// Pure, so the exact shape of every request is asserted on Linux rather than discovered
/// through an `invalid_request` on a phone.
public enum SpotifyAuth {
    public static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    public static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    public static let redirectURI = "cardash://spotify-callback"

    /// Exactly the permissions the app's requests need, and no more.
    ///
    /// Kept as one list because a missing scope surfaces only at runtime, as a 403 on the one
    /// endpoint that needed it — often long after sign-in. `SpotifyScopeTests` ties each entry
    /// to the call that requires it.
    public static let scopes: [String] = [
        "user-read-playback-state",      // GET /me/player, GET /me/player/devices
        "user-modify-playback-state",    // play, pause, next, previous, seek, transfer
        "user-read-currently-playing",   // GET /me/player/currently-playing
        "user-read-recently-played",     // GET /me/player/recently-played
        "playlist-read-private",         // GET /me/playlists (private ones)
        "playlist-read-collaborative"    // GET /me/playlists (collaborative ones)
    ]

    public static var scopeString: String {
        scopes.joined(separator: " ")
    }

    /// The URL to hand to `ASWebAuthenticationSession`.
    public static func authorizationURL(
        clientID: String,
        codeChallenge: String,
        state: String
    ) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopeString)
        ]
        return components?.url
    }

    /// What came back on the redirect.
    public enum CallbackResult: Hashable, Sendable {
        case code(String, state: String?)
        /// The user pressed Cancel, or Spotify refused. `access_denied` is the ordinary
        /// "changed my mind" case and should not be presented as a failure.
        case denied(String)
        case malformed
    }

    public static func parseCallback(_ url: URL) -> CallbackResult {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .malformed
        }
        let items = components.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        if let error = value("error") {
            return .denied(error)
        }
        guard let code = value("code"), !code.isEmpty else {
            return .malformed
        }
        return .code(code, state: value("state"))
    }

    // MARK: - Token requests
    //
    // PKCE means there is no client secret — that is the entire point, since a secret shipped
    // inside an app is not a secret. The client_id goes in the body instead.

    public static func tokenExchangeBody(
        code: String,
        codeVerifier: String,
        clientID: String
    ) -> Data {
        formEncoded([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier
        ])
    }

    public static func refreshBody(refreshToken: String, clientID: String) -> Data {
        formEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
    }

    /// `application/x-www-form-urlencoded`, with keys sorted so the output is deterministic
    /// and can be asserted directly.
    static func formEncoded(_ parameters: [String: String]) -> Data {
        // Spotify's redirect URI contains ':' and '/', which must be percent-encoded in a
        // form body. The default `.urlQueryAllowed` set leaves them alone, so it is narrowed
        // here — getting this wrong yields a redirect_uri mismatch that reads like a
        // dashboard misconfiguration.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return Data(
            parameters
                .sorted { $0.key < $1.key }
                .map { key, value in
                    let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                    let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                    return "\(encodedKey)=\(encodedValue)"
                }
                .joined(separator: "&")
                .utf8
        )
    }
}
