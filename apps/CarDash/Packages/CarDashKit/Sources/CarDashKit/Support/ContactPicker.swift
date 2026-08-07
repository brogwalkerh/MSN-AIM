import ContactsUI
import Contacts
import SwiftUI
import CarDashCore

/// The system contact picker, wrapped for SwiftUI.
///
/// The reason this app has no `NSContactsUsageDescription` and never prompts for Contacts
/// access. `CNContactPickerViewController` runs in a separate process; the app receives only
/// the entries the user tapped, and nothing else in the address book is readable. That is a
/// better deal for the user than a permission prompt, and it is why the picker is the *only*
/// way favourites get added.
///
/// The trade, stated once here because it explains the whole design: without authorization the
/// app cannot look a contact up again later, so what comes back is copied and kept.
struct ContactPicker: UIViewControllerRepresentable {
    /// Called with everything the user selected, already converted.
    let onPick: ([Favourite]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Only entries that have a number are worth offering — picking someone with no phone
        // number would produce a favourite that cannot be called or texted.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: ([Favourite]) -> Void
        private let onFinish: () -> Void

        init(onPick: @escaping ([Favourite]) -> Void, onFinish: @escaping () -> Void) {
            self.onPick = onPick
            self.onFinish = onFinish
        }

        /// Single selection: one contact, whichever number is first.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(Self.favourites(from: [contact]))
            onFinish()
        }

        /// A specific number was chosen, which is the better path when someone has several.
        func contactPicker(
            _ picker: CNContactPickerViewController,
            didSelect contactProperty: CNContactProperty
        ) {
            guard let value = contactProperty.value as? CNPhoneNumber else {
                onFinish()
                return
            }
            let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName)
            onPick([
                Favourite(
                    name: name ?? "",
                    phoneNumber: value.stringValue,
                    label: contactProperty.label.map {
                        CNLabeledValue<NSString>.localizedString(forLabel: $0)
                    }
                )
            ])
            onFinish()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onFinish()
        }

        static func favourites(from contacts: [CNContact]) -> [Favourite] {
            contacts.compactMap { contact in
                // The first number, because the picker's multi-select mode gives no way to
                // say which one — someone with a home and a mobile gets the mobile if that is
                // how their card is ordered, and can be re-added the other way.
                guard let number = contact.phoneNumbers.first else { return nil }
                return Favourite(
                    name: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                    phoneNumber: number.value.stringValue,
                    label: number.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
                )
            }
        }
    }
}
