import Foundation
import Testing
@testable import CarDashCore

@Suite("PlaybackStateMachine")
struct PlaybackStateMachineTests {
    /// `handle` is mutating, so its result is always bound before being asserted on —
    /// `#expect` evaluates through a closure that receives the subject immutably.
    private func started(_ provider: ProviderID) -> PlaybackStateMachine {
        var subject = PlaybackStateMachine()
        _ = subject.handle(.switchTo(provider))
        _ = subject.handle(.play)
        _ = subject.handle(.status(provider, .playing))
        return subject
    }

    private func isPublish(_ command: PlaybackCommand) -> Bool {
        if case .publishNowPlaying = command { return true }
        return false
    }

    // MARK: - Session ownership

    // The ordering that makes cross-process playback work at all. With our session still
    // active, Spotify starts and is immediately cut off — the classic "it plays for half
    // a second then stops" bug.
    @Test("An out-of-process provider gets the session released before it is told to play")
    func releasesSessionBeforeExternalPlayback() {
        var subject = PlaybackStateMachine()
        _ = subject.handle(.switchTo(.spotify))
        let commands = subject.handle(.play)

        let deactivate = commands.firstIndex(of: .deactivateSession)
        let tell = commands.firstIndex(of: .tell(.spotify, .play))
        #expect(deactivate != nil)
        #expect(tell != nil)
        if let deactivate, let tell {
            #expect(deactivate < tell, "told Spotify to play while still holding the session")
        }
        #expect(!commands.contains(.activateSession))
    }

    @Test("An in-process provider takes the session before playing")
    func takesSessionForLocalPlayback() {
        var subject = PlaybackStateMachine()
        _ = subject.handle(.switchTo(.localFiles))
        let commands = subject.handle(.play)

        let activate = commands.firstIndex(of: .activateSession)
        let tell = commands.firstIndex(of: .tell(.localFiles, .play))
        #expect(activate != nil)
        #expect(tell != nil)
        if let activate, let tell { #expect(activate < tell) }
    }

    // Whichever app holds the session owns the lock screen. Publishing our own metadata
    // while Spotify is the source produces two apps fighting over it, and track names
    // that flicker between them.
    @Test("Now-playing is only published when this app owns the audio")
    func nowPlayingOnlyWhenOwning() {
        var external = PlaybackStateMachine()
        _ = external.handle(.switchTo(.appleMusic))
        var externalCommands = external.handle(.play)
        externalCommands += external.handle(.item(.appleMusic, NowPlayingItem(title: "Track")))

        #expect(!externalCommands.contains(where: isPublish))
        #expect(externalCommands.contains(.clearNowPlaying))

        var local = PlaybackStateMachine()
        _ = local.handle(.switchTo(.localFiles))
        let localCommands = local.handle(.item(.localFiles, NowPlayingItem(title: "Track")))
        #expect(localCommands.contains(where: isPublish))
    }

    @Test("Every provider is classified as owning or not owning the session")
    func ownershipClassification() {
        #expect(ProviderID.localFiles.ownsAudioSession)
        #expect(ProviderID.youtube.ownsAudioSession)
        #expect(!ProviderID.spotify.ownsAudioSession)
        #expect(!ProviderID.appleMusic.ownsAudioSession)
    }

    // MARK: - Switching sources

    @Test("Switching sources pauses the old one and does not auto-play the new one")
    func switchingPausesTheOldSource() {
        var subject = started(.localFiles)
        let commands = subject.handle(.switchTo(.spotify))

        #expect(commands.contains(.tell(.localFiles, .pause)))
        #expect(!commands.contains(.tell(.spotify, .play)), "choosing a source is not a play command")
        #expect(subject.state.activeProvider == .spotify)
        #expect(subject.state.status == .idle)
        #expect(subject.state.item == nil, "stale metadata from the old source must go")
    }

    @Test("Switching to the source already selected does nothing")
    func switchingToSameProvider() {
        var subject = started(.spotify)
        let before = subject.state
        let commands = subject.handle(.switchTo(.spotify))

        #expect(commands.isEmpty)
        #expect(subject.state == before)
    }

    // MARK: - Ignoring the inactive

    // Spotify keeps reporting state after the user switches to local files. Acting on it
    // would redraw the transport bar with a track that is not playing.
    @Test("Events from a provider that is not active are ignored")
    func inactiveProviderIsIgnored() {
        var subject = started(.localFiles)
        let before = subject.state

        let status = subject.handle(.status(.spotify, .playing))
        let item = subject.handle(.item(.spotify, NowPlayingItem(title: "Other")))
        let position = subject.handle(.position(.spotify, 42))
        let lost = subject.handle(.lostConnection(.spotify))

        #expect(status.isEmpty)
        #expect(item.isEmpty)
        #expect(position.isEmpty)
        #expect(lost.isEmpty)
        #expect(subject.state == before)
    }

    // MARK: - Interruptions

    @Test("An interruption pauses playback and remembers it can resume")
    func interruptionPauses() {
        var subject = started(.localFiles)
        let paused = subject.handle(.interrupted)

        #expect(paused == [.tell(.localFiles, .pause)])
        #expect(subject.state.status == .paused)
        #expect(subject.state.pausedByInterruption)

        let resumed = subject.handle(.interruptionEndedResumable)
        #expect(resumed == [.tell(.localFiles, .play)])
        #expect(!subject.state.pausedByInterruption)
    }

    // Hanging up a call must not start music the driver deliberately silenced.
    @Test("A user pause is not resumed when an interruption ends")
    func userPauseIsNotResumed() {
        var subject = started(.localFiles)
        _ = subject.handle(.pause)
        #expect(!subject.state.pausedByInterruption)

        let resumed = subject.handle(.interruptionEndedResumable)
        #expect(resumed.isEmpty)
        #expect(subject.state.status == .paused)
    }

    // An interruption arriving during a source switch, before anything is playing. If
    // this armed a resume, ending the call would start audio that was never on.
    @Test("An interruption while nothing is playing leaves nothing to resume")
    func interruptionWhileIdle() {
        var subject = PlaybackStateMachine()
        _ = subject.handle(.switchTo(.spotify))
        _ = subject.handle(.play)
        #expect(subject.state.status == .loading)

        let interrupted = subject.handle(.interrupted)
        #expect(interrupted.isEmpty)
        #expect(!subject.state.pausedByInterruption)

        let resumed = subject.handle(.interruptionEndedResumable)
        #expect(resumed.isEmpty)
    }

    // Unplugging headphones or leaving Bluetooth range must not blast audio out of the
    // phone speaker later.
    @Test("Losing the output device pauses without arming a resume")
    func outputLossIsNotResumable() {
        var subject = started(.localFiles)
        let paused = subject.handle(.outputDeviceLost)

        #expect(paused == [.tell(.localFiles, .pause)])
        #expect(subject.state.status == .paused)
        #expect(!subject.state.pausedByInterruption)

        let resumed = subject.handle(.interruptionEndedResumable)
        #expect(resumed.isEmpty)
    }

    // MARK: - Disconnection

    @Test("Losing the provider marks it unavailable rather than pretending to play")
    func disconnection() {
        var subject = started(.spotify)
        _ = subject.handle(.lostConnection(.spotify))
        #expect(subject.state.status == .unavailable)

        _ = subject.handle(.regainedConnection(.spotify))
        #expect(subject.state.status == .paused, "reconnecting is not the same as resuming")
    }

    @Test("Disconnecting while paused does not look like playing")
    func disconnectionWhilePaused() {
        var subject = started(.spotify)
        _ = subject.handle(.pause)
        _ = subject.handle(.lostConnection(.spotify))

        #expect(subject.state.status == .unavailable)
        #expect(!subject.state.isPlaying)
    }

    // MARK: - Transport

    @Test("Transport intents are forwarded to the active provider only")
    func transportForwarding() {
        var subject = started(.spotify)

        let next = subject.handle(.next)
        let previous = subject.handle(.previous)
        let seek = subject.handle(.seek(30))

        #expect(next == [.tell(.spotify, .next)])
        #expect(previous == [.tell(.spotify, .previous)])
        #expect(seek == [.tell(.spotify, .seek(30))])
        #expect(subject.state.position == 30)
    }

    @Test("Transport intents with no source do nothing")
    func transportWithoutProvider() {
        var subject = PlaybackStateMachine()

        let play = subject.handle(.play)
        let next = subject.handle(.next)
        let toggle = subject.handle(.toggle)

        #expect(play.isEmpty)
        #expect(next.isEmpty)
        #expect(toggle.isEmpty)
    }

    @Test("Toggle follows the current state")
    func toggle() {
        var subject = started(.localFiles)

        let pausing = subject.handle(.toggle)
        #expect(pausing.contains(.tell(.localFiles, .pause)))
        #expect(subject.state.status == .paused)

        let resuming = subject.handle(.toggle)
        #expect(resuming.contains(.tell(.localFiles, .play)))
    }

    @Test("Stopping releases everything")
    func stop() {
        var subject = started(.localFiles)
        let commands = subject.handle(.stop)

        #expect(commands.contains(.deactivateSession))
        #expect(commands.contains(.clearNowPlaying))
        #expect(subject.state.activeProvider == nil)
        #expect(subject.state.status == .idle)
    }
}
