import AVFoundation
import Observation
import CarDashCore
import os

/// Plays audio files the user imported into the app.
///
/// The only source that needs no account, no network and no other app installed — which
/// makes it the one that always works, and the sensible default in a tunnel.
///
/// Imported files are *copied* into the app's container rather than referenced in place.
/// A URL from the document picker is only valid while its security scope is held, and
/// bookmarks go stale when the file moves; copying trades a little disk for a library
/// that still plays next year.
@MainActor
@Observable
public final class LocalFilesProvider: NSObject, PlaybackProvider {
    public struct Track: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let artist: String?
        public let url: URL
        public let duration: TimeInterval
    }

    public nonisolated var id: ProviderID { .localFiles }
    public private(set) var tracks: [Track] = []
    public private(set) var currentIndex: Int?

    public var isAvailable: Bool { !tracks.isEmpty }
    public var unavailableReason: String? {
        tracks.isEmpty ? "Add some audio files to play them here." : nil
    }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var sink: (@MainActor (ProviderEvent) -> Void)?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "local-files")

    private var libraryURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return base.appending(path: "CarDash/Audio", directoryHint: .isDirectory)
    }

    public override init() {
        super.init()
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        reloadLibrary()
    }

    public func attach(_ sink: @escaping @MainActor (ProviderEvent) -> Void) {
        self.sink = sink
    }

    // MARK: - Library

    public func reloadLibrary() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: nil
        )) ?? []

        tracks = urls
            .filter { !$0.hasDirectoryPath }
            .compactMap { url in
                guard let probe = try? AVAudioPlayer(contentsOf: url) else { return nil }
                return Track(
                    id: url.lastPathComponent,
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: nil,
                    url: url,
                    duration: probe.duration
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Copies picked files into the container. Returns how many were added.
    @discardableResult
    public func importFiles(from urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            // Files from the document picker live outside the sandbox and are only
            // readable while their security scope is held.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let destination = libraryURL.appending(path: url.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
                continue
            }
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                added += 1
            } catch {
                Self.log.error("could not import \(url.lastPathComponent): \(error)")
            }
        }
        if added > 0 { reloadLibrary() }
        return added
    }

    public func remove(_ track: Track) {
        try? FileManager.default.removeItem(at: track.url)
        reloadLibrary()
    }

    // MARK: - Playback

    public func play(_ track: Track) {
        guard let index = tracks.firstIndex(of: track) else { return }
        start(at: index)
    }

    public func perform(_ intent: PlaybackIntent) {
        switch intent {
        case .play:
            if player == nil { start(at: currentIndex ?? 0) } else { resume() }
        case .pause:
            player?.pause()
            stopTicking()
            sink?(.status(id, .paused))
        case .toggle:
            player?.isPlaying == true ? perform(.pause) : perform(.play)
        case .next:
            advance(by: 1)
        case .previous:
            // The convention everyone expects: back at the start of a track goes to the
            // previous one; part-way through it restarts the current one.
            if let player, player.currentTime > 3 {
                player.currentTime = 0
                sink?(.position(id, 0))
            } else {
                advance(by: -1)
            }
        case .seek(let position):
            player?.currentTime = position
            sink?(.position(id, position))
        case .stop, .switchTo:
            relinquish()
        }
    }

    public func relinquish() {
        player?.stop()
        player = nil
        stopTicking()
        sink?(.status(id, .idle))
    }

    private func start(at index: Int) {
        guard tracks.indices.contains(index) else {
            sink?(.failed(id, "Nothing to play"))
            return
        }
        let track = tracks[index]
        currentIndex = index

        do {
            let player = try AVAudioPlayer(contentsOf: track.url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player

            sink?(.item(id, NowPlayingItem(
                title: track.title,
                artist: track.artist,
                duration: track.duration,
                identifier: track.id
            )))
            sink?(.status(id, .playing))
            startTicking()
        } catch {
            Self.log.error("could not play \(track.title): \(error)")
            sink?(.failed(id, "Could not play \(track.title)"))
        }
    }

    private func resume() {
        player?.play()
        sink?(.status(id, .playing))
        startTicking()
    }

    private func advance(by offset: Int) {
        guard !tracks.isEmpty else { return }
        let next = ((currentIndex ?? 0) + offset + tracks.count) % tracks.count
        start(at: next)
    }

    /// Drives the progress bar. One second is plenty for a readout nobody stares at, and
    /// on a screen deliberately kept awake a faster timer is a real battery cost.
    private func startTicking() {
        stopTicking()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.sink?(.position(self.id, player.currentTime))
            }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }
}

extension LocalFilesProvider: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        MainActor.assumeIsolated {
            guard flag else {
                sink?(.status(id, .paused))
                return
            }
            advance(by: 1)
        }
    }
}
