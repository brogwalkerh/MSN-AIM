import AVFoundation
import CarDashCore
import os

/// Owns `AVAudioSession` and nothing else.
///
/// Kept separate because the session is a process-wide singleton with global effects:
/// activating it while Spotify is playing interrupts Spotify. Funnelling every
/// activation through one object makes it possible to say, in one place, exactly when
/// this app claims the audio.
@MainActor
public final class AudioSessionController {
    /// System events the state machine needs to know about.
    public var onEvent: ((ProviderEvent) -> Void)?

    private var isActive = false
    private static let log = Logger(subsystem: "dev.cardash", category: "audio-session")

    public init() {
        observe()
    }

    public func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            Self.log.error("could not set the audio category: \(error)")
        }
    }

    public func activate() {
        guard !isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            isActive = true
        } catch {
            Self.log.error("could not activate: \(error)")
        }
    }

    public func deactivate() {
        guard isActive else { return }
        do {
            // The option is what tells Spotify or Music they can come back. Without it
            // they stay ducked or paused indefinitely.
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        } catch {
            Self.log.error("could not deactivate: \(error)")
        }
    }

    private func observe() {
        let centre = NotificationCenter.default

        centre.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }

        centre.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleRouteChange(notification) }
        }

        // Media services really do reset — rarely, but it happens, and when it does
        // every audio object in the process is dead. Without handling it the app simply
        // goes silent for the rest of the drive with no error anywhere.
        centre.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.log.error("media services were reset — rebuilding the session")
                self?.isActive = false
                self?.configure()
                self?.onEvent?(.interrupted)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            isActive = false
            onEvent?(.interrupted)
        case .ended:
            let optionsRaw = notification
                .userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            // Only resume when the system says so. Resuming unconditionally is how an
            // app starts talking over a phone call that has not finished.
            if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                onEvent?(.interruptionEndedResumable)
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        if reason == .oldDeviceUnavailable {
            onEvent?(.outputDeviceLost)
        }
    }
}
