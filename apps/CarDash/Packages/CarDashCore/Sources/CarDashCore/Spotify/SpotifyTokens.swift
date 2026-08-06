import Foundation

/// A token response from `accounts.spotify.com/api/token`.
public struct SpotifyTokenResponse: Decodable, Hashable, Sendable {
    public let accessToken: String
    public let tokenType: String?
    public let expiresIn: TimeInterval
    /// Present on the initial exchange, and *sometimes* on refresh — see `SpotifyTokens`.
    public let refreshToken: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// The credentials the app holds between launches.
public struct SpotifyTokens: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var grantedScopes: [String]

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        grantedScopes: [String] = []
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.grantedScopes = grantedScopes
    }

    /// Builds from the initial exchange, which always carries a refresh token.
    public init?(exchange response: SpotifyTokenResponse, now: Date) {
        guard let refreshToken = response.refreshToken else { return nil }
        self.init(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(response.expiresIn),
            grantedScopes: response.scope?.split(separator: " ").map(String.init) ?? []
        )
    }

    /// Applies a refresh response.
    ///
    /// **Spotify rotates the refresh token.** A refresh response may carry a new
    /// `refresh_token`, and it must replace the stored one. Keeping the original is the
    /// classic version of this bug: sign-in works, everything works for an hour, and then
    /// authentication fails permanently with a message about an invalid grant — long after
    /// anyone would still be looking at the login code.
    ///
    /// It may equally omit the field, in which case the existing token stays valid. Both
    /// shapes are covered by fixtures.
    public func applying(_ response: SpotifyTokenResponse, now: Date) -> SpotifyTokens {
        SpotifyTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: now.addingTimeInterval(response.expiresIn),
            grantedScopes: response.scope?.split(separator: " ").map(String.init) ?? grantedScopes
        )
    }

    /// Refreshed early rather than on expiry. A token that expires mid-request produces a
    /// 401 the user sees as a stutter; a minute of slack costs nothing.
    public static let refreshLeeway: TimeInterval = 60

    public func isExpired(at date: Date) -> Bool {
        date >= expiresAt
    }

    public func needsRefresh(at date: Date, leeway: TimeInterval = SpotifyTokens.refreshLeeway) -> Bool {
        date.addingTimeInterval(leeway) >= expiresAt
    }

    /// Whether every scope the app relies on was actually granted.
    ///
    /// Spotify can return fewer scopes than were asked for. Detecting that at sign-in and
    /// prompting to reconnect is far better than a 403 on one button a week later.
    public func isMissingRequiredScopes(_ required: [String] = SpotifyAuth.scopes) -> Bool {
        guard !grantedScopes.isEmpty else { return false }
        return !Set(required).isSubset(of: Set(grantedScopes))
    }
}
