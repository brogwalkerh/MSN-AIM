import Foundation
import Testing
@testable import CarDashCore

@Suite("Spotify tokens")
struct SpotifyTokenTests {
    private let signedInAt = Date(timeIntervalSince1970: 1_754_463_600)

    private func response(_ fixture: String) throws -> SpotifyTokenResponse {
        try JSONDecoder().decode(SpotifyTokenResponse.self, from: try Fixture.data(fixture))
    }

    @Test("The initial exchange decodes into stored credentials")
    func exchange() throws {
        let decoded = try response("spotify-token-exchange")
        #expect(decoded.accessToken == "BQD_initial_access_token")
        #expect(decoded.tokenType == "Bearer")
        #expect(decoded.expiresIn == 3600)
        #expect(decoded.refreshToken == "AQC_original_refresh_token")

        let tokens = try #require(SpotifyTokens(exchange: decoded, now: signedInAt))
        #expect(tokens.accessToken == "BQD_initial_access_token")
        #expect(tokens.refreshToken == "AQC_original_refresh_token")
        #expect(tokens.expiresAt == signedInAt.addingTimeInterval(3600))
        #expect(tokens.grantedScopes.count == SpotifyAuth.scopes.count)
        #expect(!tokens.isMissingRequiredScopes())
    }

    // An exchange response without a refresh token cannot be stored as a session — there
    // would be no way to come back an hour later.
    @Test("An exchange with no refresh token is refused")
    func exchangeWithoutRefreshToken() {
        let incomplete = SpotifyTokenResponse(
            accessToken: "BQD",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: nil,
            scope: nil
        )
        #expect(SpotifyTokens(exchange: incomplete, now: signedInAt) == nil)
    }

    // The bug this whole type exists to prevent. Spotify rotates the refresh token on PKCE
    // refresh; keeping the original one works for exactly one hour and then fails forever.
    @Test("A rotated refresh token replaces the stored one")
    func rotation() throws {
        let initial = try #require(SpotifyTokens(exchange: try response("spotify-token-exchange"), now: signedInAt))
        let refreshedAt = signedInAt.addingTimeInterval(3500)
        let rotated = initial.applying(try response("spotify-token-refresh-rotated"), now: refreshedAt)

        #expect(rotated.accessToken == "BQD_second_access_token")
        #expect(rotated.refreshToken == "AQC_rotated_refresh_token")
        #expect(rotated.refreshToken != initial.refreshToken, "the old one is now dead")
        #expect(rotated.expiresAt == refreshedAt.addingTimeInterval(3600))
    }

    // The other half: Spotify may equally omit the field, and treating that absence as
    // "no refresh token" would sign the user out just as thoroughly.
    @Test("A refresh with no new token keeps the existing one")
    func noRotation() throws {
        let initial = try #require(SpotifyTokens(exchange: try response("spotify-token-exchange"), now: signedInAt))
        let refreshedAt = signedInAt.addingTimeInterval(3500)
        let refreshed = initial.applying(try response("spotify-token-refresh-plain"), now: refreshedAt)

        #expect(refreshed.accessToken == "BQD_third_access_token")
        #expect(refreshed.refreshToken == "AQC_original_refresh_token")
        #expect(refreshed.expiresAt == refreshedAt.addingTimeInterval(3600))
    }

    @Test("Repeated rotation always tracks the newest token")
    func repeatedRotation() throws {
        var tokens = try #require(SpotifyTokens(exchange: try response("spotify-token-exchange"), now: signedInAt))
        let rotatedResponse = try response("spotify-token-refresh-rotated")

        for hour in 1...5 {
            tokens = tokens.applying(rotatedResponse, now: signedInAt.addingTimeInterval(3600 * Double(hour)))
        }
        #expect(tokens.refreshToken == "AQC_rotated_refresh_token")
        #expect(tokens.expiresAt == signedInAt.addingTimeInterval(3600 * 6))
    }

    // A refresh that drops the scope field must not be read as "no scopes granted",
    // which would make the app think it needs to prompt for reconnection.
    @Test("A refresh without a scope field keeps the granted scopes")
    func scopesSurviveRefresh() throws {
        let initial = try #require(SpotifyTokens(exchange: try response("spotify-token-exchange"), now: signedInAt))
        let scopeless = SpotifyTokenResponse(
            accessToken: "BQD_next",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: nil,
            scope: nil
        )
        let refreshed = initial.applying(scopeless, now: signedInAt.addingTimeInterval(3500))
        #expect(refreshed.grantedScopes == initial.grantedScopes)
    }

    @Test("Expiry is refreshed a minute early, so a token cannot die mid-request")
    func expiryArithmetic() throws {
        let tokens = try #require(SpotifyTokens(exchange: try response("spotify-token-exchange"), now: signedInAt))
        let expiry = signedInAt.addingTimeInterval(3600)

        #expect(!tokens.isExpired(at: expiry.addingTimeInterval(-1)))
        #expect(tokens.isExpired(at: expiry))
        #expect(tokens.isExpired(at: expiry.addingTimeInterval(1)))

        #expect(!tokens.needsRefresh(at: expiry.addingTimeInterval(-61)))
        #expect(tokens.needsRefresh(at: expiry.addingTimeInterval(-60)), "the leeway boundary")
        #expect(tokens.needsRefresh(at: expiry.addingTimeInterval(-30)))
        #expect(tokens.needsRefresh(at: expiry.addingTimeInterval(600)), "already long dead")
        #expect(SpotifyTokens.refreshLeeway == 60)
    }

    // Spotify can grant fewer scopes than were asked for. Catching that at sign-in beats
    // discovering it as a 403 on one button a week later.
    @Test("Partial scope grants are detected")
    func partialScopes() {
        let full = SpotifyTokens(
            accessToken: "a", refreshToken: "r", expiresAt: signedInAt,
            grantedScopes: SpotifyAuth.scopes
        )
        #expect(!full.isMissingRequiredScopes())

        let partial = SpotifyTokens(
            accessToken: "a", refreshToken: "r", expiresAt: signedInAt,
            grantedScopes: Array(SpotifyAuth.scopes.dropLast())
        )
        #expect(partial.isMissingRequiredScopes())

        let extra = SpotifyTokens(
            accessToken: "a", refreshToken: "r", expiresAt: signedInAt,
            grantedScopes: SpotifyAuth.scopes + ["user-read-email"]
        )
        #expect(!extra.isMissingRequiredScopes(), "more than asked for is not a problem")

        // Older stored credentials predate scope recording; treating an empty list as
        // "missing everything" would sign out a working session on upgrade.
        let legacy = SpotifyTokens(accessToken: "a", refreshToken: "r", expiresAt: signedInAt)
        #expect(!legacy.isMissingRequiredScopes())
    }

    @Test("Stored credentials survive a round trip through JSON")
    func codableRoundTrip() throws {
        let tokens = try #require(SpotifyTokens(exchange: try response("spotify-token-exchange"), now: signedInAt))
        let encoded = try JSONEncoder().encode(tokens)
        let decoded = try JSONDecoder().decode(SpotifyTokens.self, from: encoded)
        #expect(decoded == tokens)
    }
}
