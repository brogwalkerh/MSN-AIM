import Foundation

/// How often to ask Spotify what it is doing.
///
/// Controlling Spotify over the Web API means there are no push updates, so track changes are
/// noticed by polling. That is a real cost — every poll is a request against a rate limit, and
/// on a screen deliberately kept awake it is also radio time. The cadence is therefore a
/// function of whether anyone can see the answer.
///
/// Pure, so the policy is asserted rather than assumed.
public enum SpotifyPollPolicy {
    public struct Conditions: Hashable, Sendable {
        public var isPlaying: Bool
        /// Whether a Spotify tile is currently on screen.
        public var isTileVisible: Bool
        /// Whether the app is in the foreground at all.
        public var isForeground: Bool
        /// Set after a 429, from the `Retry-After` header.
        public var backoffUntil: Date?

        public init(
            isPlaying: Bool,
            isTileVisible: Bool,
            isForeground: Bool,
            backoffUntil: Date? = nil
        ) {
            self.isPlaying = isPlaying
            self.isTileVisible = isTileVisible
            self.isForeground = isForeground
            self.backoffUntil = backoffUntil
        }
    }

    /// Seconds until the next poll, or nil to stop polling entirely.
    public static func interval(for conditions: Conditions, now: Date) -> TimeInterval? {
        // Backing off wins over everything. Continuing to poll through a 429 is how a
        // temporary limit becomes a long one.
        if let backoffUntil = conditions.backoffUntil, backoffUntil > now {
            return backoffUntil.timeIntervalSince(now)
        }

        // Nothing in the background. Playback continues in Spotify's own process and the
        // lock screen is Spotify's, so there is nothing here to keep up to date — polling
        // would be pure battery and rate limit for a UI nobody can see.
        guard conditions.isForeground else { return nil }

        switch (conditions.isPlaying, conditions.isTileVisible) {
        case (true, true):
            // Fast enough that a track change is noticed before it feels stale.
            return 3
        case (true, false):
            // Playing, but the driver has swapped the tile for the map. The transport bar
            // may still be on screen, so it cannot stop entirely.
            return 10
        case (false, true):
            // Paused and visible: the only thing that changes is someone pressing play
            // elsewhere.
            return 15
        case (false, false):
            return 60
        }
    }

    /// Roughly how many requests an hour of driving costs, for sanity-checking against
    /// Spotify's limits.
    public static func requestsPerHour(for conditions: Conditions, now: Date = Date()) -> Int {
        guard let interval = interval(for: conditions, now: now), interval > 0 else { return 0 }
        return Int(3600 / interval)
    }
}
