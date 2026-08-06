import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit
import CarDashCore
import os

/// Sign-in and token lifetime for Spotify.
///
/// Everything that can be decided without I/O — the URL, the bodies, base64url, expiry
/// arithmetic, refresh-token rotation — lives in `CarDashCore` and is tested on Linux.
/// What is left here is the three things that genuinely need a device: the SHA-256, the
/// web-authentication sheet, and the Keychain.
@MainActor
@Observable
public final class SpotifyAuthService: NSObject {
    public enum State: Equatable {
        case notConfigured
        case signedOut
        case authorizing
        case signedIn
        case failed(String)
    }

    public private(set) var state: State = .signedOut

    public var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    @ObservationIgnored private var tokens: SpotifyTokens?
    @ObservationIgnored private let clientID: String?
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    /// Held so that concurrent callers awaiting a token share one refresh rather than
    /// racing several against each other — each of which would rotate the refresh token
    /// and invalidate the others.
    @ObservationIgnored private var refreshTask: Task<String, Swift.Error>?
    @ObservationIgnored private static let keychainKey = "spotify.tokens"
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "spotify-auth")

    public init(clientID: String? = AppConfiguration.spotifyClientID) {
        self.clientID = clientID
        super.init()

        guard clientID != nil else {
            state = .notConfigured
            return
        }
        tokens = Keychain.load(SpotifyTokens.self, for: Self.keychainKey)
        state = tokens == nil ? .signedOut : .signedIn
    }

    // MARK: - Sign in

    public func signIn() async {
        guard let clientID else {
            state = .notConfigured
            return
        }
        guard state != .authorizing else { return }
        state = .authorizing

        do {
            let verifier = Self.newVerifier()
            let challenge = PKCE.challenge(fromSHA256Digest: Self.sha256(of: verifier))
            let expectedState = Self.newVerifier()

            guard let url = SpotifyAuth.authorizationURL(
                clientID: clientID,
                codeChallenge: challenge,
                state: expectedState
            ) else {
                state = .failed(SpotifyAPIError.notConfigured.userFacingMessage)
                return
            }

            let callback = try await presentAuthorization(at: url)

            switch SpotifyAuth.parseCallback(callback) {
            case .code(let code, let returnedState):
                // The state check is what stops an injected redirect from swapping in
                // someone else's authorization code.
                guard returnedState == expectedState else {
                    state = .failed("Sign-in could not be verified. Try again.")
                    return
                }
                try await exchange(code: code, verifier: verifier, clientID: clientID)

            case .denied(let reason):
                // Pressing Cancel is not a failure worth an error message.
                state = reason == "access_denied" ? .signedOut : .failed(reason)

            case .malformed:
                state = .failed("Spotify sent back something unreadable.")
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            state = .signedOut
        } catch {
            Self.log.error("sign-in failed: \(error)")
            state = .failed("Could not sign in to Spotify.")
        }
    }

    public func signOut() {
        tokens = nil
        try? Keychain.remove(Self.keychainKey)
        state = clientID == nil ? .notConfigured : .signedOut
    }

    private func presentAuthorization(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                // Matching on the scheme alone; the path is checked by `parseCallback`.
                callbackURLScheme: URL(string: SpotifyAuth.redirectURI)?.scheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAPIError.malformedResponse("no callback"))
                }
            }
            session.presentationContextProvider = self
            // Deliberately *not* ephemeral: reusing the Safari session means someone
            // already signed into Spotify on the phone taps once rather than typing a
            // password into a phone clamped to a windscreen.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    // MARK: - Tokens

    /// A valid access token, refreshing first if it is close to expiry.
    public func accessToken() async throws -> String {
        guard let clientID else { throw SpotifyAPIError.notConfigured }
        guard let current = tokens else { throw SpotifyAPIError.unauthorized }

        guard current.needsRefresh(at: Date()) else { return current.accessToken }
        return try await refresh(clientID: clientID)
    }

    /// Forces a refresh, for the one-retry path after a 401.
    public func refreshedAccessToken() async throws -> String {
        guard let clientID else { throw SpotifyAPIError.notConfigured }
        guard tokens != nil else { throw SpotifyAPIError.unauthorized }
        return try await refresh(clientID: clientID)
    }

    private func refresh(clientID: String) async throws -> String {
        // Several tiles can want a token in the same instant. Because Spotify rotates the
        // refresh token, letting two refreshes run concurrently means the second presents
        // a token the first has already invalidated — and the user is signed out.
        if let refreshTask { return try await refreshTask.value }

        let task = Task<String, Swift.Error> { [weak self] in
            guard let self, let existing = self.tokens else { throw SpotifyAPIError.unauthorized }

            var request = URLRequest(url: SpotifyAuth.tokenEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = SpotifyAuth.refreshBody(
                refreshToken: existing.refreshToken,
                clientID: clientID
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200..<300).contains(status) else {
                // A rejected refresh token cannot be recovered from; anything else may be
                // transient, and signing the user out over a flaky tunnel would be rude.
                if status == 400 || status == 401 { self.signOut() }
                throw SpotifyAPIError.from(status: status, body: data) ?? .unauthorized
            }

            let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            // `applying` is where rotation is handled — it keeps the new refresh token
            // when one is sent and the old one when it is not.
            let updated = existing.applying(decoded, now: Date())
            self.store(updated)
            return updated.accessToken
        }

        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func exchange(code: String, verifier: String, clientID: String) async throws {
        var request = URLRequest(url: SpotifyAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpotifyAuth.tokenExchangeBody(
            code: code,
            codeVerifier: verifier,
            clientID: clientID
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            state = .failed(SpotifyAPIError.from(status: status, body: data)?.userFacingMessage
                ?? "Spotify refused the sign-in.")
            return
        }

        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        guard let new = SpotifyTokens(exchange: decoded, now: Date()) else {
            state = .failed("Spotify did not return a refresh token.")
            return
        }

        // Fewer scopes than were asked for means some buttons will 403 later. Saying so
        // now beats one control mysteriously not working next week.
        if new.isMissingRequiredScopes() {
            Self.log.warning("Spotify granted a subset of the requested scopes")
        }

        store(new)
        state = .signedIn
    }

    private func store(_ new: SpotifyTokens) {
        tokens = new
        do {
            try Keychain.store(new, for: Self.keychainKey)
        } catch {
            // Playback still works this launch; it just will not survive a restart.
            Self.log.error("could not persist Spotify tokens: \(error)")
        }
    }

    // MARK: - Crypto
    //
    // The only two lines CarDashCore cannot host, which is why the PKCE type takes bytes.

    private static func sha256(of verifier: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(verifier.utf8)))
    }

    private static func newVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<64).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return PKCE.verifier(fromRandomBytes: bytes)
    }
}

extension SpotifyAuthService: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
