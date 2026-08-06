import Foundation
import Testing
@testable import CarDashCore

@Suite("Spotify error mapping")
struct SpotifyAPIErrorTests {
    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test(
        "Successful statuses are not errors",
        arguments: [200, 201, 202, 204]
    )
    func success(status: Int) {
        #expect(SpotifyAPIError.from(status: status) == nil)
    }

    @Test("401 is a refresh, not a sign-out")
    func unauthorized() {
        let error = SpotifyAPIError.from(status: 401, body: body(#"{"error":{"status":401,"message":"The access token expired"}}"#))
        #expect(error == .unauthorized)
        #expect(error?.isRecoverableByRefresh == true)
    }

    // A free account gets 403 on every transport command. Saying *why* is the difference
    // between a useful message and "something went wrong".
    @Test("403 with a PREMIUM_REQUIRED reason names the actual problem")
    func premiumByReason() {
        let error = SpotifyAPIError.from(
            status: 403,
            body: body(#"{"error":{"status":403,"message":"Player command failed: Premium required","reason":"PREMIUM_REQUIRED"}}"#)
        )
        #expect(error == .premiumRequired)
        #expect(error?.isRecoverableByRefresh == false, "retrying with a new token changes nothing")
    }

    // Some 403s carry the explanation only in the message. Falling back to it catches the
    // same condition rather than showing a raw Spotify string.
    @Test("403 mentioning Premium in the message alone is still the Premium gate")
    func premiumByMessage() {
        let error = SpotifyAPIError.from(
            status: 403,
            body: body(#"{"error":{"status":403,"message":"Player command failed: Premium required"}}"#)
        )
        #expect(error == .premiumRequired)
    }

    @Test("Other 403s carry Spotify's own explanation through")
    func otherForbidden() {
        let error = SpotifyAPIError.from(
            status: 403,
            body: body(#"{"error":{"status":403,"message":"Player command failed: Restriction violated","reason":"UNKNOWN"}}"#)
        )
        #expect(error == .forbidden("Player command failed: Restriction violated"))
        #expect(error?.userFacingMessage == "Player command failed: Restriction violated")
    }

    // The single most important mapping in this file. A phone that has just started the
    // app has no active Spotify device, and 404 is what the API says about it. Presented
    // as an error, the tile reads as broken on every first launch.
    @Test("404 NO_ACTIVE_DEVICE is a state, not a failure")
    func noActiveDevice() {
        let error = SpotifyAPIError.from(
            status: 404,
            body: body(#"{"error":{"status":404,"message":"Player command failed: No active device found","reason":"NO_ACTIVE_DEVICE"}}"#)
        )
        #expect(error == .noActiveDevice)
        #expect(error?.userFacingMessage.contains("Choose where to play") == true)
    }

    @Test("A 404 without that reason is an ordinary missing resource")
    func genuine404() {
        let error = SpotifyAPIError.from(
            status: 404,
            body: body(#"{"error":{"status":404,"message":"Non existing id"}}"#)
        )
        #expect(error == .server(status: 404, message: "Non existing id"))
    }

    @Test("429 honours Retry-After")
    func rateLimited() {
        #expect(SpotifyAPIError.from(status: 429, retryAfter: 17) == .rateLimited(retryAfter: 17))
        // Spotify does not always send the header; backing off by nothing is how a short
        // limit becomes a long one.
        #expect(SpotifyAPIError.from(status: 429) == .rateLimited(retryAfter: 5))
    }

    @Test("Server errors keep their status")
    func serverErrors() {
        #expect(SpotifyAPIError.from(status: 500) == .server(status: 500, message: nil))
        #expect(
            SpotifyAPIError.from(status: 502, body: body(#"{"error":{"status":502,"message":"Bad gateway"}}"#))
                == .server(status: 502, message: "Bad gateway")
        )
    }

    // The token endpoint reports errors as {"error": "invalid_grant"} — a string where the
    // Web API puts an object. Reading it as an object must fail softly, not trap.
    @Test(
        "Bodies that are not the Web API's error shape are tolerated",
        arguments: [
            #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#,
            "",
            "not json",
            "[]",
            "{}"
        ]
    )
    func unexpectedErrorBodies(raw: String) {
        let error = SpotifyAPIError.from(status: 400, body: body(raw))
        #expect(error == .server(status: 400, message: nil))
    }

    @Test("Every case has something a driver could read at a glance")
    func messages() {
        let cases: [SpotifyAPIError] = [
            .unauthorized, .premiumRequired, .noActiveDevice, .rateLimited(retryAfter: 5),
            .forbidden("nope"), .malformedResponse("junk"), .server(status: 500, message: nil),
            .notConfigured
        ]
        for error in cases {
            #expect(!error.userFacingMessage.isEmpty)
            // Raw decoding diagnostics are not something to put in front of a driver.
            #expect(!error.userFacingMessage.contains("junk"))
        }
    }
}

@Suite("Spotify polling cadence")
struct SpotifyPollPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_754_463_600)

    private func conditions(
        playing: Bool,
        visible: Bool,
        foreground: Bool = true,
        backoff: Date? = nil
    ) -> SpotifyPollPolicy.Conditions {
        SpotifyPollPolicy.Conditions(
            isPlaying: playing,
            isTileVisible: visible,
            isForeground: foreground,
            backoffUntil: backoff
        )
    }

    @Test("Cadence follows whether anyone can see the answer")
    func cadence() {
        #expect(SpotifyPollPolicy.interval(for: conditions(playing: true, visible: true), now: now) == 3)
        #expect(SpotifyPollPolicy.interval(for: conditions(playing: true, visible: false), now: now) == 10)
        #expect(SpotifyPollPolicy.interval(for: conditions(playing: false, visible: true), now: now) == 15)
        #expect(SpotifyPollPolicy.interval(for: conditions(playing: false, visible: false), now: now) == 60)
    }

    // Spotify keeps playing in its own process and owns the lock screen, so there is no
    // CarDash UI to keep current — polling there is battery and rate limit for nothing.
    @Test("Nothing is polled in the background")
    func background() {
        #expect(SpotifyPollPolicy.interval(for: conditions(playing: true, visible: true, foreground: false), now: now) == nil)
        #expect(SpotifyPollPolicy.interval(for: conditions(playing: false, visible: false, foreground: false), now: now) == nil)
    }

    // Continuing to poll through a 429 is how a temporary limit becomes a long one, so
    // backoff has to beat every other consideration including the fastest cadence.
    @Test("An active backoff wins over everything")
    func backoffWins() {
        let until = now.addingTimeInterval(30)
        let interval = SpotifyPollPolicy.interval(
            for: conditions(playing: true, visible: true, backoff: until),
            now: now
        )
        #expect(interval == 30)
    }

    @Test("An expired backoff is ignored")
    func expiredBackoff() {
        let interval = SpotifyPollPolicy.interval(
            for: conditions(playing: true, visible: true, backoff: now.addingTimeInterval(-1)),
            now: now
        )
        #expect(interval == 3)
    }

    // Backoff outranks the foreground check too: a 429 taken just before backgrounding
    // must still be waited out rather than silently forgotten on the next resume.
    @Test("Backoff still applies in the background")
    func backoffInBackground() {
        let interval = SpotifyPollPolicy.interval(
            for: conditions(playing: true, visible: true, foreground: false, backoff: now.addingTimeInterval(20)),
            now: now
        )
        #expect(interval == 20)
    }

    // The point of the whole policy: an hour of driving must stay far below Spotify's
    // limits even in the worst case.
    @Test("The fastest cadence is still a modest request budget")
    func requestBudget() {
        let worst = SpotifyPollPolicy.requestsPerHour(for: conditions(playing: true, visible: true), now: now)
        #expect(worst == 1200)

        let hidden = SpotifyPollPolicy.requestsPerHour(for: conditions(playing: true, visible: false), now: now)
        #expect(hidden == 360)

        let backgrounded = SpotifyPollPolicy.requestsPerHour(
            for: conditions(playing: true, visible: true, foreground: false),
            now: now
        )
        #expect(backgrounded == 0)
    }
}
