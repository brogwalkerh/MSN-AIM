import Foundation

/// A canned message.
///
/// The point of canned messages in a car is that choosing one is a single tap on a large
/// target, so the set is short and fixed rather than editable. A screen where you compose text
/// is a screen you are reading instead of the road, and iOS will not let the app send without a
/// tap anyway — so the win available here is making the tap count, not automating it away.
public struct QuickReply: Hashable, Sendable, Identifiable {
    public let id: String
    /// What the button says. Short enough to read at a glance.
    public let title: String
    public let systemImage: String
    /// What gets put in the message field.
    public let template: Template

    public enum Template: Hashable, Sendable {
        /// Sent exactly as written.
        case literal(String)
        /// Carries the arrival time when a route is running, and falls back to a plain
        /// sentence when there is none — a reply that says "arriving at " with nothing after
        /// it is worse than one that never mentioned a time.
        case arrivalTime(prefix: String, fallback: String)
    }

    public init(id: String, title: String, systemImage: String, template: Template) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.template = template
    }
}

/// What the app knows when a reply is being written.
public struct QuickReplyContext: Hashable, Sendable {
    /// Seconds until arrival, when a route is being navigated.
    public var estimatedTimeRemaining: TimeInterval?
    /// Now, injected so the rendering is testable rather than clock-dependent.
    public var now: Date

    public init(estimatedTimeRemaining: TimeInterval? = nil, now: Date = Date()) {
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.now = now
    }

    public var arrivalDate: Date? {
        guard let remaining = estimatedTimeRemaining, remaining > 0, remaining.isFinite else {
            return nil
        }
        return now.addingTimeInterval(remaining)
    }
}

public enum QuickReplies {
    /// The fixed set. Ordered by how often each is likely to be the right answer while moving.
    public static let all: [QuickReply] = [
        QuickReply(
            id: "onMyWay",
            title: "On my way",
            systemImage: "car.fill",
            template: .arrivalTime(
                prefix: "On my way — should be there about ",
                fallback: "On my way."
            )
        ),
        QuickReply(
            id: "runningLate",
            title: "Running late",
            systemImage: "clock.fill",
            template: .arrivalTime(
                prefix: "Running late, sorry — more like ",
                fallback: "Running late, sorry."
            )
        ),
        QuickReply(
            id: "driving",
            title: "Driving",
            systemImage: "steeringwheel",
            template: .literal("I'm driving — I'll reply when I stop.")
        ),
        QuickReply(
            id: "callYou",
            title: "Call you",
            systemImage: "phone.fill",
            template: .literal("Can't talk now, I'll call you shortly.")
        ),
        QuickReply(
            id: "here",
            title: "Here",
            systemImage: "mappin.and.ellipse",
            template: .literal("I'm here.")
        )
    ]

    public static func reply(_ id: String) -> QuickReply? {
        all.first { $0.id == id }
    }

    /// Renders a reply's body.
    ///
    /// Pure, and taking the clock as an input, so the awkward cases — no route, an arrival time
    /// that has already passed, a route that reports an infinite time because the speed was
    /// zero — are asserted rather than discovered in a message someone actually sent.
    public static func render(
        _ reply: QuickReply,
        context: QuickReplyContext,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        switch reply.template {
        case .literal(let text):
            return text

        case .arrivalTime(let prefix, let fallback):
            guard let arrival = context.arrivalDate else { return fallback }
            return prefix + timeString(arrival, locale: locale, timeZone: timeZone) + "."
        }
    }

    /// Short local time — "4:35 PM" or "16:35" depending on the reader's region.
    ///
    /// `DateFormatter` with `.short` rather than a literal format string, so a 24-hour region
    /// gets 24-hour time. It is also the formatter that behaves identically on Linux, which is
    /// where this gets tested.
    static func timeString(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
