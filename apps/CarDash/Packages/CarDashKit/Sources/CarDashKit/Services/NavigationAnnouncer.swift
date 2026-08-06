import AVFoundation
import CarDashCore
import os

/// Speaks turn instructions over whatever is playing.
///
/// The audio session dance is the whole point. Spotify and the Music app play in another
/// process, so ducking them is not something the app can do directly — it is a property
/// of the session category it activates. `.voicePrompt` with `.duckOthers` lowers the
/// other app's audio for the duration and restores it afterwards, and
/// `.interruptSpokenAudioAndMixWithOthers` pauses a podcast rather than talking over it.
///
/// Deactivating with `.notifyOthersOnDeactivation` afterwards is what tells the other app
/// to come back up. Skipping it leaves music quiet for the rest of the drive.
@MainActor
public final class NavigationAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegate()
    private static let log = Logger(subsystem: "dev.cardash", category: "announcer")

    public var isEnabled = true

    public init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] in
            self?.deactivateSession()
        }
    }

    public func announce(_ prompt: ManeuverPrompt) {
        speak(prompt.text)
    }

    public func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }
        activateSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
        } catch {
            Self.log.error("could not duck for a prompt: \(error)")
        }
    }

    private func deactivateSession() {
        guard !synthesizer.isSpeaking else { return }
        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Self.log.error("could not release the session: \(error)")
        }
    }
}

/// Separate from the announcer because `AVSpeechSynthesizerDelegate` is not
/// main-actor-annotated; the callbacks do arrive on the main thread, which
/// `assumeIsolated` asserts rather than assumes silently.
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (@MainActor () -> Void)?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated { onFinish?() }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated { onFinish?() }
    }
}
