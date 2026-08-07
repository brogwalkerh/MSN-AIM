import Foundation

/// The small amount of phone-number handling this app actually needs.
///
/// Explicitly *not* a phone-number library. There is no parsing of country codes, no formatting
/// by region, no validation against numbering plans — all of that is a large problem and none of
/// it is needed to put a name on a button and hand a `tel:` URL to iOS, which does its own
/// interpretation anyway.
///
/// What is needed is one thing: deciding when two saved numbers are the same, so adding a
/// favourite twice does not produce two buttons.
public enum PhoneNumber {
    /// Digits, plus a leading `+` if there was one.
    ///
    /// `+44 7700 900123`, `(+44) 7700-900123` and `+447700900123` all normalise to the same
    /// string. Note this deliberately does *not* equate `+447700900123` with `07700900123`:
    /// deciding those are the same number requires knowing the country, and guessing wrong
    /// would silently merge two different people.
    public static func normalised(_ raw: String) -> String {
        var digits = ""
        var sawLeadingPlus = false

        for character in raw {
            if character == "+", digits.isEmpty, !sawLeadingPlus {
                sawLeadingPlus = true
            } else if character.isNumber {
                digits.append(character)
            }
        }

        return sawLeadingPlus ? "+" + digits : digits
    }

    /// Enough digits to plausibly be a number rather than an extension or a typo.
    ///
    /// Short codes exist and are as short as three digits, so the floor is deliberately low —
    /// the aim is to catch nothing-at-all, not to police what the user saved.
    public static func isDiallable(_ raw: String) -> Bool {
        let digits = normalised(raw).filter(\.isNumber)
        return digits.count >= 3 && digits.count <= 20
    }

    public static func isSameNumber(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalised(lhs)
        let right = normalised(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    /// `tel:` URL string for placing a call.
    ///
    /// iOS shows a confirmation before connecting, so this cannot dial silently. Returns nil
    /// rather than a broken URL for anything undiallable, so the caller can disable the button
    /// instead of opening a URL that does nothing.
    public static func telURLString(for raw: String) -> String? {
        guard isDiallable(raw) else { return nil }
        // Only the normalised digits go into the URL. Spaces and brackets from the address
        // book would need escaping, and iOS ignores them anyway.
        return "tel:" + normalised(raw)
    }

    /// `sms:` URL string, with the body prefilled.
    ///
    /// Used only as the fallback when `MFMessageComposeViewController` is unavailable — the
    /// in-app composer is preferred because it does not throw the driver out of the dashboard.
    public static func smsURLString(for raw: String, body: String) -> String? {
        guard isDiallable(raw) else { return nil }
        // `&` before `body` is not a typo: it is the shape Apple documents for the sms scheme,
        // and the more obvious `?body=` is ignored on some iOS versions.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "sms:" + normalised(raw) + "&body=" + encoded
    }
}
