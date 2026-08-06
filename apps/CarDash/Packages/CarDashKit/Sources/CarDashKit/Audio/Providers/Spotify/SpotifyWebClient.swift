import Foundation
import CarDashCore
import os

/// Every call to api.spotify.com the app makes.
///
/// Thin on purpose: it attaches the token, retries once after a 401, and hands the bytes
/// to a decoder in `CarDashCore`. Nothing here decides anything, which is what keeps the
/// decisions testable on Linux.
@MainActor
public final class SpotifyWebClient {
    private let auth: SpotifyAuthService
    private let session: URLSession
    private static let base = URL(string: "https://api.spotify.com/v1")!
    private static let log = Logger(subsystem: "dev.cardash", category: "spotify-api")

    public init(auth: SpotifyAuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - Reads

    public func playback() async throws -> SpotifyPlayback {
        let data = try await send(.get, "/me/player")
        return try SpotifyPlayerDecoder.playback(from: data)
    }

    public func devices() async throws -> [SpotifyDevice] {
        let data = try await send(.get, "/me/player/devices")
        return try SpotifyPlayerDecoder.devices(from: data)
    }

    public func playlists(limit: Int = 50) async throws -> [SpotifyPlaylist] {
        let data = try await send(.get, "/me/playlists", query: ["limit": String(limit)])
        return try SpotifyLibraryDecoder.playlists(from: data)
    }

    public func recentlyPlayed(limit: Int = 50) async throws -> [SpotifyRecentTrack] {
        let data = try await send(.get, "/me/player/recently-played", query: ["limit": String(limit)])
        return try SpotifyLibraryDecoder.recentlyPlayed(from: data)
    }

    // MARK: - Transport
    //
    // Every one of these can answer 404 NO_ACTIVE_DEVICE, which the caller treats as a
    // prompt to pick a device rather than as a failure.

    public func play(contextURI: String? = nil, trackURIs: [String]? = nil) async throws {
        var body: [String: Any] = [:]
        if let contextURI { body["context_uri"] = contextURI }
        if let trackURIs { body["uris"] = trackURIs }
        _ = try await send(.put, "/me/player/play", body: body.isEmpty ? nil : body)
    }

    public func pause() async throws {
        _ = try await send(.put, "/me/player/pause")
    }

    public func next() async throws {
        _ = try await send(.post, "/me/player/next")
    }

    public func previous() async throws {
        _ = try await send(.post, "/me/player/previous")
    }

    public func seek(to position: TimeInterval) async throws {
        let milliseconds = max(0, Int(position * 1000))
        _ = try await send(.put, "/me/player/seek", query: ["position_ms": String(milliseconds)])
    }

    /// Moves playback to a device, which is how "Play on this iPhone" is implemented.
    ///
    /// `play: true` matters — transferring without it moves a *paused* player, so the
    /// button appears to do nothing.
    public func transfer(to deviceID: String, play: Bool = true) async throws {
        _ = try await send(.put, "/me/player", body: ["device_ids": [deviceID], "play": play])
    }

    // MARK: - Transport plumbing

    private enum Method: String {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
    }

    private func send(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> Data {
        let token = try await auth.accessToken()

        do {
            return try await perform(method, path, query: query, body: body, token: token)
        } catch let error as SpotifyAPIError where error.isRecoverableByRefresh {
            // Exactly one retry. A token can expire between the freshness check and the
            // request reaching Spotify; a second 401 means something else is wrong and
            // looping would only turn it into a spin.
            let refreshed = try await auth.refreshedAccessToken()
            return try await perform(method, path, query: query, body: body, token: refreshed)
        }
    }

    private func perform(
        _ method: Method,
        _ path: String,
        query: [String: String],
        body: [String: Any]?,
        token: String
    ) async throws -> Data {
        var components = URLComponents(
            url: Self.base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw SpotifyAPIError.malformedResponse("could not build \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // A dashboard in a moving car should give up rather than hang on a control the
        // driver has already stopped looking at.
        request.timeoutInterval = 12

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method != .get {
            // Spotify's transport endpoints reject a PUT with no body declared at all on
            // some paths; an empty JSON object is accepted everywhere.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.malformedResponse("no HTTP response")
        }

        let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
        if let error = SpotifyAPIError.from(status: http.statusCode, body: data, retryAfter: retryAfter) {
            throw error
        }
        // 204 is a success with an empty body — the decoders read that as "idle".
        return data
    }
}
