import Foundation

/// A YouTube video the user has chosen to play.
///
/// The title is optional and arrives later: it comes from the player itself once the video has
/// loaded, because looking it up beforehand would need the YouTube Data API, an API key and a
/// quota — none of which is worth it for a list the driver populates by hand.
public struct YouTubeVideo: Codable, Hashable, Sendable, Identifiable {
    /// The eleven-character video id.
    public let id: String
    public var title: String?
    /// Seconds into the video to begin at, from a `t=` in the shared link.
    public var startSeconds: Int
    public var addedAt: Date

    public init(id: String, title: String? = nil, startSeconds: Int = 0, addedAt: Date) {
        self.id = id
        self.title = title
        self.startSeconds = max(0, startSeconds)
        self.addedAt = addedAt
    }

    public var displayTitle: String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "YouTube video"
        }
        return title
    }

    /// Thumbnail served straight from YouTube's image host — no API key, no request quota.
    public var thumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }
}

/// Pulling a video id out of whatever the user pasted.
///
/// This is the part worth testing properly. A shared YouTube link arrives in about eight
/// shapes — `youtu.be`, `/shorts/`, `/embed/`, `/live/`, `music.youtube.com`, with or without a
/// playlist, a timestamp or a tracking parameter — and getting it wrong means a tile that says
/// "that isn't a YouTube link" about a link the user copied from YouTube.
public enum YouTubeLink {
    /// Characters a video id is made of, per YouTube's own format.
    static let idCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )
    public static let idLength = 11

    public static func isValidID(_ candidate: String) -> Bool {
        candidate.count == idLength
            && candidate.unicodeScalars.allSatisfy(idCharacters.contains)
    }

    /// The video id and start time in whatever was pasted, or nil.
    ///
    /// Accepts a bare id too: someone who copies just the id should not be told it is invalid.
    public static func parse(_ input: String) -> (id: String, startSeconds: Int)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isValidID(trimmed) { return (trimmed, 0) }

        // Links are pasted from share sheets, which sometimes omit the scheme. Without this a
        // bare "youtu.be/…" fails to parse as a URL at all.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate) else { return nil }

        guard let host = components.host?.lowercased() else { return nil }
        let queryItems = components.queryItems ?? []
        let start = startSeconds(from: queryItems)

        // youtu.be/ID — the path is the id.
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return isValidID(id) ? (id, start) : nil
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

        // watch?v=ID — the ordinary desktop link.
        if let value = queryItems.first(where: { $0.name == "v" })?.value, isValidID(value) {
            return (value, start)
        }

        // /shorts/ID, /embed/ID, /live/ID, /v/ID all put the id in the second path component.
        let parts = components.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
            return isValidID(parts[1]) ? (parts[1], start) : nil
        }

        return nil
    }

    public static func video(from input: String, now: Date) -> YouTubeVideo? {
        guard let parsed = parse(input) else { return nil }
        return YouTubeVideo(id: parsed.id, startSeconds: parsed.startSeconds, addedAt: now)
    }

    /// Reads `t=` or `start=`, in either the plain-seconds or the `1h2m3s` form.
    static func startSeconds(from queryItems: [URLQueryItem]) -> Int {
        guard let raw = queryItems.first(where: { $0.name == "t" || $0.name == "start" })?.value
        else { return 0 }

        if let plain = Int(raw) { return max(0, plain) }

        // "1h2m30s", "90s", "2m" — YouTube uses this form in share links from the app.
        var total = 0
        var digits = ""
        for character in raw.lowercased() {
            if character.isNumber {
                digits.append(character)
                continue
            }
            let value = Int(digits) ?? 0
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return 0   // not a form we understand; starting at zero is safe
            }
            digits = ""
        }
        // A trailing number with no unit means seconds.
        total += Int(digits) ?? 0
        return max(0, total)
    }
}

/// The recently played list the tile offers.
///
/// There is no search, and that is deliberate rather than unfinished: searching means typing,
/// and the app already refuses to show a list at all while the car is moving. What is useful in
/// a car is the handful of things you already watch.
public struct YouTubeRecents: Codable, Hashable, Sendable {
    public private(set) var videos: [YouTubeVideo]

    /// Enough to be useful, few enough to stay a glance rather than a scroll.
    public static let capacity = 20

    public init(videos: [YouTubeVideo] = []) {
        self.videos = Array(videos.prefix(Self.capacity))
    }

    public var isEmpty: Bool { videos.isEmpty }

    /// Adds, or moves an existing entry back to the front.
    ///
    /// Most recent first, because the thing you played last is overwhelmingly the thing you
    /// want next — and because a list that reorders itself is easier to live with than one that
    /// grows a duplicate every time.
    public func adding(_ video: YouTubeVideo) -> YouTubeRecents {
        var kept = videos.filter { $0.id != video.id }
        // A title learned on a previous play is worth keeping if this one has not loaded yet.
        var entry = video
        if entry.title == nil {
            entry.title = videos.first { $0.id == video.id }?.title
        }
        kept.insert(entry, at: 0)
        return YouTubeRecents(videos: kept)
    }

    /// Fills in a title once the player reports one.
    public func naming(_ id: String, _ title: String) -> YouTubeRecents {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return YouTubeRecents(videos: videos.map { video in
            guard video.id == id else { return video }
            var named = video
            named.title = trimmed
            return named
        })
    }

    public func removing(_ id: String) -> YouTubeRecents {
        YouTubeRecents(videos: videos.filter { $0.id != id })
    }
}
