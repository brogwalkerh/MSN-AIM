import Foundation
import Testing
@testable import CarDashCore

@Suite("Phone numbers")
struct PhoneNumberTests {
    // The only job normalisation has: deciding when two saved numbers are the same person, so
    // adding a favourite twice does not produce two identical buttons.
    @Test(
        "Punctuation is irrelevant to identity",
        arguments: [
            "+44 7700 900123",
            "(+44) 7700-900123",
            "+44-7700-900123",
            "+44.7700.900123",
            "+447700900123"
        ]
    )
    func punctuationIgnored(raw: String) {
        #expect(PhoneNumber.normalised(raw) == "+447700900123")
        #expect(PhoneNumber.isSameNumber(raw, "+447700900123"))
    }

    @Test("A leading plus is kept, because it is the only part that carries meaning")
    func leadingPlus() {
        #expect(PhoneNumber.normalised("+15551234567") == "+15551234567")
        #expect(PhoneNumber.normalised("15551234567") == "15551234567")
        // A plus anywhere else is punctuation.
        #expect(PhoneNumber.normalised("555+1234") == "5551234")
        #expect(PhoneNumber.normalised("++4477") == "+4477")
    }

    // Guessing that +447700900123 and 07700900123 are the same requires knowing the country.
    // Guessing wrong silently merges two different people, which is worse than two entries.
    @Test("National and international forms are not assumed to be the same")
    func noCountryGuessing() {
        #expect(!PhoneNumber.isSameNumber("+447700900123", "07700900123"))
        #expect(!PhoneNumber.isSameNumber("+15551234567", "5551234567"))
    }

    @Test("Letters and whitespace are stripped")
    func letters() {
        #expect(PhoneNumber.normalised("555-CALL") == "555")
        #expect(PhoneNumber.normalised("  555 123 4567  ") == "5551234567")
        #expect(PhoneNumber.normalised("") == "")
    }

    @Test(
        "Nothing-at-all is not diallable",
        arguments: ["", "   ", "abc", "+", "12", "-()"]
    )
    func undiallable(raw: String) {
        #expect(!PhoneNumber.isDiallable(raw))
        #expect(PhoneNumber.telURLString(for: raw) == nil)
    }

    // Short codes are three digits, so the floor is low on purpose: the aim is to catch
    // an empty field, not to police what the user saved.
    @Test("Short codes and ordinary numbers are both diallable")
    func diallable() {
        #expect(PhoneNumber.isDiallable("611"))
        #expect(PhoneNumber.isDiallable("+447700900123"))
        #expect(PhoneNumber.isDiallable("(555) 123-4567"))
    }

    @Test("Two empty numbers are not 'the same number'")
    func emptyIsNotEqual() {
        #expect(!PhoneNumber.isSameNumber("", ""))
        #expect(!PhoneNumber.isSameNumber("abc", "xyz"))
    }

    @Test("The tel URL carries only digits")
    func telURL() {
        #expect(PhoneNumber.telURLString(for: "(555) 123-4567") == "tel:5551234567")
        #expect(PhoneNumber.telURLString(for: "+44 7700 900123") == "tel:+447700900123")
    }

    @Test("The sms URL percent-encodes the body")
    func smsURL() throws {
        let url = try #require(PhoneNumber.smsURLString(for: "5551234567", body: "On my way — 4:35."))
        #expect(url.hasPrefix("sms:5551234567&body="))
        // A raw space or ampersand here would truncate the message at that character.
        #expect(!url.dropFirst("sms:5551234567&body=".count).contains(" "))
        #expect(url.contains("%20"))
        // Ensure it survives being made into an actual URL, which is the whole point.
        #expect(URL(string: url) != nil)
    }
}

@Suite("Favourites")
struct FavouriteTests {
    private func person(_ name: String, _ number: String) -> Favourite {
        Favourite(name: name, phoneNumber: number)
    }

    @Test(
        "Initials come from the first letters of the first two words",
        arguments: [
            ("Ada Lovelace", "AL"),
            ("ada lovelace", "AL"),
            ("Ada", "A"),
            ("Ada Byron King", "AB"),
            ("  Ada   Lovelace  ", "AL"),
            ("Ada 2 Lovelace", "AL")
        ]
    )
    func initials(name: String, expected: String) {
        #expect(person(name, "5551234567").initials == expected)
    }

    // A photo would need Contacts authorization, so the avatar is initials — and a favourite
    // saved without a name still has to render as something.
    @Test("A nameless favourite falls back to the number, never to nothing")
    func namelessFallback() {
        let anonymous = person("", "5551234567")
        #expect(anonymous.initials == "5")
        #expect(anonymous.displayName == "5551234567")

        let punctuation = person("!!!", "+447700900123")
        #expect(punctuation.initials == "4", "the plus is not a digit")
    }

    @Test("Identity is the digits, not the formatting")
    func identity() {
        #expect(person("Ada", "(555) 123-4567").normalisedNumber == "5551234567")
        #expect(person("Ada", "555 123 4567").isDiallable)
        #expect(!person("Ada", "").isDiallable)
    }

    @Test("Round trips through JSON, because it is what gets persisted")
    func codable() throws {
        let original = Favourite(name: "Ada Lovelace", phoneNumber: "+44 7700 900123", label: "mobile")
        let decoded = try JSONDecoder().decode(
            Favourite.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(decoded == original)
        #expect(decoded.id == original.id, "the identity has to survive, or the grid reshuffles")
    }
}

@Suite("Favourites list")
struct FavouritesListTests {
    private func person(_ name: String, _ number: String) -> Favourite {
        Favourite(name: name, phoneNumber: number)
    }

    @Test("Adding appends")
    func adding() {
        let list = FavouritesList()
            .adding(person("Ada", "5551110000"))
            .adding(person("Grace", "5552220000"))

        #expect(list.count == 2)
        #expect(list.entries.map(\.name) == ["Ada", "Grace"])
    }

    // Picking the same person twice is an ordinary slip. Two identical buttons would be worse
    // than the second tap doing nothing.
    @Test("The same number cannot be added twice, however it is written")
    func deduplicates() {
        let list = FavouritesList()
            .adding(person("Ada", "+44 7700 900123"))
            .adding(person("Ada Lovelace", "+447700900123"))
            .adding(person("Ada L", "(+44) 7700-900123"))

        #expect(list.count == 1)
        #expect(list.entries[0].name == "Ada", "an existing entry is not relabelled by a duplicate add")
    }

    @Test("A batch from the picker deduplicates within itself too")
    func batchDeduplicates() {
        let list = FavouritesList().adding(contentsOf: [
            person("Ada", "5551110000"),
            person("Ada again", "555 111 0000"),
            person("Grace", "5552220000")
        ])
        #expect(list.count == 2)
    }

    @Test("Undiallable entries are refused")
    func refusesUndiallable() {
        let list = FavouritesList().adding(person("Nobody", ""))
        #expect(list.isEmpty)
    }

    // Past about a dozen faces the grid stops being something you can hit without looking.
    @Test("The list stops at capacity rather than growing without bound")
    func capacity() {
        var list = FavouritesList()
        for index in 0..<(FavouritesList.capacity + 5) {
            list = list.adding(person("P\(index)", "555000\(String(format: "%04d", index))"))
        }
        #expect(list.count == FavouritesList.capacity)
        #expect(list.isFull)
        #expect(list.entries.first?.name == "P0", "the earliest are kept, not the latest")
    }

    @Test("An over-long list handed to the initialiser is trimmed, not trusted")
    func initialiserTrims() {
        let many = (0..<40).map { person("P\($0)", "5550000\($0)") }
        #expect(FavouritesList(entries: many).count == FavouritesList.capacity)
    }

    @Test("Removing works by id and by number")
    func removing() {
        let ada = person("Ada", "5551110000")
        let list = FavouritesList().adding(ada).adding(person("Grace", "5552220000"))

        #expect(list.removing(ada.id).count == 1)
        #expect(list.removing(number: "555 111 0000").count == 1)
        #expect(list.removing(number: "5559999999").count == 2, "removing an absent number is a no-op")
        #expect(list.removing(UUID()).count == 2)
    }

    @Test("Reordering moves one entry and leaves the rest in order")
    func moving() {
        let list = FavouritesList().adding(contentsOf: [
            person("A", "5550000001"),
            person("B", "5550000002"),
            person("C", "5550000003")
        ])

        #expect(list.moving(from: 0, to: 2).entries.map(\.name) == ["B", "C", "A"])
        #expect(list.moving(from: 2, to: 0).entries.map(\.name) == ["C", "A", "B"])
        #expect(list.moving(from: 1, to: 1).entries.map(\.name) == ["A", "B", "C"])
    }

    // A drag that ends somewhere unexpected should do nothing, not trap.
    @Test(
        "Out-of-range moves are survivable",
        arguments: [(-1, 0), (9, 0), (0, 99), (0, -5)]
    )
    func movingOutOfRange(source: Int, destination: Int) {
        let list = FavouritesList().adding(contentsOf: [
            person("A", "5550000001"),
            person("B", "5550000002")
        ])
        let moved = list.moving(from: source, to: destination)
        #expect(moved.count == 2)
        #expect(Set(moved.entries.map(\.name)) == ["A", "B"])
    }

    @Test("Empty list operations are all no-ops")
    func emptyList() {
        let empty = FavouritesList()
        #expect(empty.isEmpty)
        #expect(!empty.isFull)
        #expect(empty.moving(from: 0, to: 0).isEmpty)
        #expect(empty.removing(UUID()).isEmpty)
        #expect(empty.prefix(5).isEmpty)
        #expect(!empty.contains(number: "5551234567"))
    }

    @Test("Round trips through JSON")
    func codable() throws {
        let list = FavouritesList().adding(contentsOf: [
            person("Ada", "5551110000"),
            person("Grace", "5552220000")
        ])
        let decoded = try JSONDecoder().decode(
            FavouritesList.self,
            from: try JSONEncoder().encode(list)
        )
        #expect(decoded == list)
    }
}

@Suite("Quick replies")
struct QuickReplyTests {
    private let posix = Locale(identifier: "en_US_POSIX")
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_754_463_600)

    @Test("Literal replies are sent as written")
    func literal() throws {
        let driving = try #require(QuickReplies.reply("driving"))
        let text = QuickReplies.render(driving, context: QuickReplyContext(now: now))
        #expect(text == "I'm driving — I'll reply when I stop.")
    }

    @Test("A running route puts the arrival time in the message")
    func arrivalTime() throws {
        let onMyWay = try #require(QuickReplies.reply("onMyWay"))
        // 25 minutes out.
        let context = QuickReplyContext(estimatedTimeRemaining: 1500, now: now)
        let text = QuickReplies.render(onMyWay, context: context, locale: posix, timeZone: utc)

        #expect(text.hasPrefix("On my way — should be there about "))
        #expect(text.hasSuffix("."))
        // 07:00 UTC plus 25 minutes. Asserted by parts rather than as one string, because
        // the separator and the AM marker are the formatter's business, not this test's.
        #expect(text.contains("7:25") || text.contains("07:25"))
    }

    // A reply reading "arriving at ." is worse than one that never mentioned a time.
    @Test("With no route the fallback sentence is used, never a dangling prefix")
    func noRouteFallback() throws {
        let onMyWay = try #require(QuickReplies.reply("onMyWay"))
        let text = QuickReplies.render(onMyWay, context: QuickReplyContext(now: now))
        #expect(text == "On my way.")
        #expect(!text.hasSuffix("about ."))
    }

    // A stationary car makes the guidance engine divide by a speed of zero, and a route that
    // has already been completed reports nothing left. Neither should reach a message.
    @Test(
        "Degenerate arrival times fall back rather than rendering nonsense",
        arguments: [0.0, -60.0, .infinity, -.infinity]
    )
    func degenerateETA(remaining: TimeInterval) throws {
        let context = QuickReplyContext(estimatedTimeRemaining: remaining, now: now)
        #expect(context.arrivalDate == nil)

        let late = try #require(QuickReplies.reply("runningLate"))
        #expect(QuickReplies.render(late, context: context) == "Running late, sorry.")
    }

    @Test("A NaN time remaining is not an arrival time")
    func nanETA() {
        let context = QuickReplyContext(estimatedTimeRemaining: .nan, now: now)
        #expect(context.arrivalDate == nil)
    }

    @Test("Every reply renders to something sendable in both contexts", arguments: QuickReplies.all)
    func allRender(reply: QuickReply) {
        let withRoute = QuickReplyContext(estimatedTimeRemaining: 900, now: now)
        let without = QuickReplyContext(now: now)

        for context in [withRoute, without] {
            let text = QuickReplies.render(reply, context: context, locale: posix, timeZone: utc)
            #expect(!text.isEmpty)
            #expect(!text.hasSuffix(" ."), "a template left a dangling separator")
            #expect(!text.contains("  "), "a template left a double space")
        }
        #expect(!reply.title.isEmpty)
        #expect(!reply.systemImage.isEmpty)
    }

    @Test("Ids are unique and stable, since they are what a tile persists")
    func identifiers() {
        let ids = QuickReplies.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(QuickReplies.reply("onMyWay") != nil)
        #expect(QuickReplies.reply("nonsense") == nil)
    }
}
