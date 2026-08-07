import Foundation

/// Someone you call or text from the car.
///
/// The name and number are stored rather than a `CNContact` identifier, and that is a
/// deliberate trade rather than laziness. `CNContactPickerViewController` runs out of process
/// and hands back only what the user picked, which is why this app asks for no Contacts
/// permission at all. The price is that it cannot look a contact up again later — resolving an
/// identifier *would* need authorization. So what the picker returns is what gets kept.
///
/// The consequence to be honest about: if someone changes their number in Contacts, the
/// favourite here goes stale until it is re-added.
public struct Favourite: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    /// As the user's address book had it — kept verbatim for display.
    public var phoneNumber: String
    /// "mobile", "home", whatever the address book called this number.
    public var label: String?

    public init(id: UUID = UUID(), name: String, phoneNumber: String, label: String? = nil) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.label = label
    }

    /// What identity means here: two entries are the same person-and-number if the digits
    /// match, whatever punctuation the address book used.
    public var normalisedNumber: String {
        PhoneNumber.normalised(phoneNumber)
    }

    public var isDiallable: Bool {
        PhoneNumber.isDiallable(phoneNumber)
    }

    /// Up to two letters for the avatar, because a photo would need Contacts authorization.
    ///
    /// Falls back to the number's first digit rather than rendering an empty circle — a
    /// favourite saved with a blank name is still something the user chose.
    public var initials: String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: \.isLetter) }

        let letters = words.prefix(2).compactMap { word -> String? in
            guard let letter = word.first(where: \.isLetter) else { return nil }
            return String(letter).uppercased()
        }

        if letters.isEmpty {
            return normalisedNumber.first(where: \.isNumber).map(String.init) ?? "?"
        }
        return letters.joined()
    }

    /// Name if there is one, otherwise the number — never an empty label.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? phoneNumber : trimmed
    }
}
