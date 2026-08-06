import Foundation

/// Spotify's HTTP statuses, turned into things the app can act on.
///
/// The mapping matters because three of these are not failures in any ordinary sense: 204 is
/// "nothing is playing", 401 is "refresh and retry", and 404 on a playback command is "no
/// device is active yet", which for a phone in a car is the *normal* starting state. Treating
/// any of them as an error produces a tile that reports Spotify as broken when it is fine.
public enum SpotifyAPIError: Error, Hashable, Sendable {
    /// The access token expired. Refresh and retry once.
    case unauthorized
    /// Premium is required for this endpoint. Not recoverable by retrying.
    case premiumRequired
    /// No device is currently active. Offer a transfer target.
    case noActiveDevice
    /// Rate limited; wait this long.
    case rateLimited(retryAfter: TimeInterval)
    case forbidden(String)
    case malformedResponse(String)
    case server(status: Int, message: String?)
    case notConfigured

    /// Maps a response.
    ///
    /// - Parameters:
    ///   - status: HTTP status code.
    ///   - body: response body, used to distinguish the two meanings of 403 and 404.
    ///   - retryAfter: the `Retry-After` header, in seconds, if present.
    /// - Returns: nil when the response is a success.
    public static func from(
        status: Int,
        body: Data = Data(),
        retryAfter: TimeInterval? = nil
    ) -> SpotifyAPIError? {
        switch status {
        case 200..<300:
            return nil

        case 401:
            return .unauthorized

        case 403:
            // Spotify signals the Premium gate in the body's reason, not the status. A free
            // account gets 403 on every transport command, and telling the user *why* is the
            // difference between a useful message and "something went wrong".
            let reason = self.reason(in: body)
            if reason == "PREMIUM_REQUIRED" || message(in: body)?.localizedCaseInsensitiveContains("premium") == true {
                return .premiumRequired
            }
            return .forbidden(message(in: body) ?? "Spotify refused that request")

        case 404:
            // 404 on a playback endpoint means no active device, which is expected rather
            // than exceptional. Spotify uses the same status for a genuinely missing
            // resource, so the reason field is what separates them.
            if self.reason(in: body) == "NO_ACTIVE_DEVICE" {
                return .noActiveDevice
            }
            return .server(status: 404, message: message(in: body))

        case 429:
            // Spotify's Retry-After is in seconds. Honouring it is the difference between
            // backing off and being locked out for longer.
            return .rateLimited(retryAfter: retryAfter ?? 5)

        default:
            return .server(status: status, message: message(in: body))
        }
    }

    /// True when retrying after a token refresh is worth attempting.
    public var isRecoverableByRefresh: Bool {
        self == .unauthorized
    }

    public var userFacingMessage: String {
        switch self {
        case .unauthorized:
            return "Spotify sign-in expired. Reconnecting…"
        case .premiumRequired:
            return "Spotify Premium is required to control playback."
        case .noActiveDevice:
            return "No Spotify device is playing. Choose where to play."
        case .rateLimited:
            return "Spotify is rate limiting; slowing down."
        case .forbidden(let message):
            return message
        case .malformedResponse:
            return "Spotify sent something unexpected."
        case .server(let status, let message):
            return message ?? "Spotify error \(status)."
        case .notConfigured:
            return "Add a Spotify Client ID to connect."
        }
    }

    // MARK: - Body parsing
    //
    // Errors arrive as {"error": {"status": n, "message": "...", "reason": "..."}}. The reason
    // is absent on many errors, so both lookups are best-effort.

    static func reason(in body: Data) -> String? {
        errorObject(in: body)?["reason"] as? String
    }

    static func message(in body: Data) -> String? {
        errorObject(in: body)?["message"] as? String
    }

    private static func errorObject(in body: Data) -> [String: Any]? {
        guard !body.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return json["error"] as? [String: Any]
    }
}
