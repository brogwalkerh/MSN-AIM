import MessageUI
import SwiftUI
import UIKit
import CarDashCore

/// The system message composer, prefilled.
///
/// **iOS will not let any app send a message without a human tap, and this is the closest an
/// app may get.** The sheet arrives with the recipient and the text already filled in; the send
/// button is the user's. There is no entitlement, no private API and no version of this that
/// sends silently — which is worth stating plainly in the UI rather than leaving the driver to
/// wonder why nothing was sent.
///
/// The composer is preferred over an `sms:` URL because the URL throws the driver out of the
/// dashboard and into the Messages app; this stays put.
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (MessageComposeResult) -> Void

    @MainActor
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = recipients
        composer.body = body
        return composer
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            // Dismissing is the delegate's job — the controller does not do it itself, and
            // forgetting leaves the sheet stuck over the dashboard.
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}

/// Placing a call.
///
/// Trivial enough to be inline, except that the two failure modes are worth naming: a device
/// with no telephony (an iPad, or an iPod touch) cannot open `tel:` at all, and iOS always
/// shows its own confirmation before connecting. Neither is an error.
@MainActor
enum PhoneDialer {
    static func canDial(_ number: String) -> Bool {
        guard let string = PhoneNumber.telURLString(for: number),
              let url = URL(string: string) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// - Returns: false when there was nothing to dial, so the caller can say so rather than
    ///   leaving a button that appears to do nothing.
    @discardableResult
    static func dial(_ number: String) -> Bool {
        guard let string = PhoneNumber.telURLString(for: number),
              let url = URL(string: string),
              UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
