import Foundation
import Testing
@testable import CarDashCore

// The RFC 7636 Appendix B worked example, which publishes the verifier, the SHA-256
// octets of its ASCII encoding, and the resulting challenge. Asserting against it is the
// only way to know base64url is right without a live authorization server: every mistake
// here — standard base64, retained padding, hashing the UTF-16 — produces a challenge the
// server rejects with a bare `invalid_grant`, which points at nothing.
private enum RFC7636 {
    static let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

    static let digest: [UInt8] = [
        19, 211, 30, 150, 26, 26, 216, 236, 47, 22, 177, 12, 76, 152, 46, 8,
        118, 168, 120, 173, 109, 241, 68, 86, 110, 225, 137, 74, 203, 112, 249, 195
    ]

    static let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
}

@Suite("PKCE")
struct PKCETests {
    @Test("The RFC 7636 Appendix B challenge is reproduced exactly")
    func rfcVector() {
        #expect(PKCE.challenge(fromSHA256Digest: RFC7636.digest) == RFC7636.challenge)
    }

    @Test("The RFC's own verifier passes validation")
    func rfcVerifierIsValid() {
        #expect(PKCE.isValidVerifier(RFC7636.verifier))
        #expect(RFC7636.verifier.count == PKCE.minimumVerifierLength)
    }

    // base64url differs from base64 in exactly three places, and all three are silent.
    @Test(
        "base64url substitutes - and _ and drops padding",
        arguments: [
            ([UInt8]([251, 255, 190]), "-_--"),
            ([UInt8]([255]), "_w"),
            ([UInt8]([255, 238]), "_-4"),
            ([UInt8]([]), "")
        ]
    )
    func base64URL(bytes: [UInt8], expected: String) {
        let encoded = PKCE.base64URLEncoded(Data(bytes))
        #expect(encoded == expected)
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
    }

    @Test("A verifier built from random bytes uses only the permitted alphabet")
    func verifierAlphabet() {
        // Every byte value, so no byte can map outside the alphabet.
        let bytes = (0...255).map { UInt8($0) }
        let verifier = PKCE.verifier(fromRandomBytes: bytes)
        #expect(PKCE.isValidVerifier(verifier))
    }

    @Test("Length is clamped into the range the authorization server accepts")
    func verifierLength() {
        let tooLong = PKCE.verifier(fromRandomBytes: Array(repeating: 7, count: 400))
        #expect(tooLong.count == PKCE.maximumVerifierLength)

        // Too few bytes must not produce a verifier the server will reject outright.
        let tooShort = PKCE.verifier(fromRandomBytes: [1, 2, 3])
        #expect(tooShort.count == PKCE.minimumVerifierLength)
        #expect(PKCE.isValidVerifier(tooShort))

        let typical = PKCE.verifier(fromRandomBytes: Array(repeating: 200, count: 64))
        #expect(typical.count == 64)
    }

    @Test("The same bytes always give the same verifier")
    func deterministic() {
        let bytes: [UInt8] = (0..<64).map { UInt8(($0 * 37) % 256) }
        #expect(PKCE.verifier(fromRandomBytes: bytes) == PKCE.verifier(fromRandomBytes: bytes))
    }

    @Test(
        "Characters outside RFC 7636 §4.1 are rejected",
        arguments: ["", "short", String(repeating: "a", count: 129), String(repeating: "a", count: 42),
                    String(repeating: "a", count: 42) + "+", String(repeating: "a", count: 42) + "/"]
    )
    func invalidVerifiers(candidate: String) {
        #expect(!PKCE.isValidVerifier(candidate))
    }
}

@Suite("Spotify authorization requests")
struct SpotifyAuthRequestTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { first, _ in first }
    }

    @Test("The authorize URL carries every parameter Spotify requires")
    func authorizeURL() throws {
        let url = try #require(
            SpotifyAuth.authorizationURL(
                clientID: "abc123",
                codeChallenge: RFC7636.challenge,
                state: "state-value"
            )
        )
        #expect(url.host == "accounts.spotify.com")
        #expect(url.path == "/authorize")

        let parameters = query(url)
        #expect(parameters["client_id"] == "abc123")
        #expect(parameters["response_type"] == "code")
        #expect(parameters["redirect_uri"] == SpotifyAuth.redirectURI)
        #expect(parameters["code_challenge_method"] == "S256", "plain would be accepted by nothing worth using")
        #expect(parameters["code_challenge"] == RFC7636.challenge)
        #expect(parameters["state"] == "state-value")
        #expect(parameters["scope"] == SpotifyAuth.scopeString)
    }

    // An empty client ID is the shipped default until the user registers an app, and must
    // be a supported state rather than a crash or a request that 400s.
    @Test("No client ID means no URL")
    func emptyClientID() {
        #expect(SpotifyAuth.authorizationURL(clientID: "", codeChallenge: "c", state: "s") == nil)
    }

    @Test("The redirect URI matches the app's declared URL scheme")
    func redirectURI() {
        #expect(SpotifyAuth.redirectURI == "cardash://spotify-callback")
        #expect(SpotifyAuth.redirectURI.hasPrefix("cardash://"))
    }

    // Each scope exists because a specific call needs it. A missing one shows up as a 403
    // on one button, possibly days later.
    @Test("Scopes cover exactly the endpoints the app calls")
    func scopes() {
        #expect(Set(SpotifyAuth.scopes) == Set([
            "user-read-playback-state",
            "user-modify-playback-state",
            "user-read-currently-playing",
            "user-read-recently-played",
            "playlist-read-private",
            "playlist-read-collaborative"
        ]))
        #expect(SpotifyAuth.scopes.count == Set(SpotifyAuth.scopes).count, "no duplicates")
        #expect(!SpotifyAuth.scopeString.contains(","), "Spotify separates scopes with spaces")
        #expect(!SpotifyAuth.scopes.contains("user-read-email"), "nothing is asked for that is not used")
    }

    @Test("A successful callback yields the code and state")
    func callbackSuccess() throws {
        let url = try #require(URL(string: "cardash://spotify-callback?code=AQD123&state=xyz"))
        #expect(SpotifyAuth.parseCallback(url) == .code("AQD123", state: "xyz"))
    }

    // Pressing Cancel is not a failure, and a tile that says "Spotify error" because
    // someone changed their mind is worse than one that says nothing.
    @Test("A denied callback is reported as denial, not malformation")
    func callbackDenied() throws {
        let url = try #require(URL(string: "cardash://spotify-callback?error=access_denied&state=xyz"))
        #expect(SpotifyAuth.parseCallback(url) == .denied("access_denied"))
    }

    @Test(
        "Callbacks with nothing usable are malformed",
        arguments: [
            "cardash://spotify-callback",
            "cardash://spotify-callback?state=xyz",
            "cardash://spotify-callback?code=&state=xyz"
        ]
    )
    func callbackMalformed(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(SpotifyAuth.parseCallback(url) == .malformed)
    }

    @Test("The token exchange body is form-encoded with the verifier and no secret")
    func exchangeBody() throws {
        let data = SpotifyAuth.tokenExchangeBody(
            code: "AQD123",
            codeVerifier: RFC7636.verifier,
            clientID: "abc123"
        )
        let body = try #require(String(data: data, encoding: .utf8))

        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=AQD123"))
        #expect(body.contains("client_id=abc123"))
        #expect(body.contains("code_verifier=\(RFC7636.verifier)"), "the RFC charset needs no escaping")
        // The colon and slashes must be escaped or Spotify reports a redirect_uri mismatch,
        // which reads like a dashboard problem and is not one.
        #expect(body.contains("redirect_uri=cardash%3A%2F%2Fspotify-callback"))
        #expect(!body.contains("client_secret"), "PKCE exists so no secret ships in the app")
    }

    @Test("The refresh body carries the client ID, since PKCE has no secret to authenticate with")
    func refreshBody() throws {
        let data = SpotifyAuth.refreshBody(refreshToken: "AQC_original", clientID: "abc123")
        let body = try #require(String(data: data, encoding: .utf8))

        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=AQC_original"))
        #expect(body.contains("client_id=abc123"))
        #expect(!body.contains("client_secret"))
    }

    @Test("Form encoding escapes characters that would otherwise split the body")
    func formEncoding() throws {
        let data = SpotifyAuth.formEncoded(["a": "x&y=z", "b": "p q+r"])
        let body = try #require(String(data: data, encoding: .utf8))
        // Sorted by key, so this is assertable verbatim.
        #expect(body == "a=x%26y%3Dz&b=p%20q%2Br")
    }
}
