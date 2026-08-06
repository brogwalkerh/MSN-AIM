import Foundation
import CarDashCore
import os

/// One protocol, two implementations.
///
/// The app ships on Open-Meteo, which needs no key, no signup and no entitlement, so the
/// weather tile works before any developer-portal chores are done. `WeatherKitProvider`
/// slots in behind the same protocol in Phase 9 once the capability is enabled — a
/// one-line change at the composition root rather than a rewrite of the tile.
public protocol WeatherProviding: Sendable {
    func snapshot(for coordinate: Coordinate) async throws -> WeatherSnapshot
}

/// Free, keyless, and rate-limited generously enough for one car.
public struct OpenMeteoProvider: WeatherProviding {
    private let session: URLSession
    private let clock: @Sendable () -> Date

    public init(session: URLSession = .shared, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.clock = clock
    }

    public func snapshot(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        guard let url = OpenMeteoDecoder.requestURL(for: coordinate) else {
            throw WeatherError.malformedResponse("could not build request URL")
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherError.requestFailed(status: http.statusCode)
        }

        return try OpenMeteoDecoder.decode(data, coordinate: coordinate, fetchedAt: clock())
    }
}

/// Adds caching in front of any provider.
///
/// Two things it prevents. Coordinates are rounded to roughly a kilometre before being
/// used as the key, so driving does not invalidate the cache on every GPS fix and fetch
/// an identical forecast at 60 mph. And a short TTL keeps the whole day's usage near a
/// hundred calls — comfortably inside Open-Meteo's limit, and inside WeatherKit's
/// 500,000/month when that swaps in.
public actor CachingWeatherProvider: WeatherProviding {
    private let upstream: any WeatherProviding
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date
    private var cache: [Coordinate: WeatherSnapshot] = [:]
    /// De-duplicates concurrent requests: three tiles asking at once should be one call.
    private var inFlight: [Coordinate: Task<WeatherSnapshot, any Error>] = [:]

    private static let log = Logger(subsystem: "dev.cardash", category: "weather")

    public init(
        wrapping upstream: any WeatherProviding,
        ttl: TimeInterval = 15 * 60,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.upstream = upstream
        self.ttl = ttl
        self.clock = clock
    }

    public func snapshot(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        let key = coordinate.rounded()
        let now = clock()

        if let cached = cache[key], cached.isFresh(at: now, ttl: ttl) {
            return cached
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { [upstream] in
            try await upstream.snapshot(for: key)
        }
        inFlight[key] = task

        defer { inFlight[key] = nil }

        do {
            let snapshot = try await task.value
            cache[key] = snapshot
            return snapshot
        } catch {
            // A stale forecast beats an empty tile on a road with no signal. Only the
            // freshness check above is skipped — nothing pretends the data is current.
            if let stale = cache[key] {
                Self.log.notice("weather fetch failed, serving stale data: \(error)")
                return stale
            }
            throw error
        }
    }
}
