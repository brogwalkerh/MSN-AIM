import SwiftUI
import UniformTypeIdentifiers
import CarDashCore

enum MusicSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .music,
            title: "Music",
            systemImage: "music.note",
            blurb: "Spotify, your music library, and your own files.",
            capabilities: [.producesAudio, .singleton]
        ) { context in
            AnyView(MusicPaneView(context: context))
        }
    }
}

struct MusicPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme
    @State private var importing = false

    private var audio: AudioCoordinator { context.services.audio }

    var body: some View {
        VStack(spacing: 6) {
            sourcePicker

            // Browsing a list is a parked-car activity. While moving it is replaced by
            // the transport controls, which are the only part usable at speed.
            if context.services.location.isDriving {
                drivingView
            } else {
                library
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                audio.localFiles.importFiles(from: urls)
            }
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 6) {
            ForEach([ProviderID.spotify, .appleMusic, .localFiles], id: \.self) { provider in
                Button {
                    audio.send(.switchTo(provider))
                } label: {
                    Text(provider.displayName)
                        .font(DashFont.label(12))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            audio.state.activeProvider == provider ? theme.accent : theme.tile,
                            in: Capsule()
                        )
                        .foregroundStyle(
                            audio.state.activeProvider == provider ? theme.background : theme.primaryText
                        )
                }
            }
            Spacer(minLength: 0)
            Button {
                importing = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(theme.tile, in: Circle())
                    .foregroundStyle(theme.primaryText)
            }
            .accessibilityLabel("Add audio files")
        }
    }

    @ViewBuilder
    private var library: some View {
        switch audio.state.activeProvider {
        case .spotify:
            SpotifySourceView(provider: audio.spotify, audio: audio)
        case .appleMusic:
            appleMusicLibrary
        default:
            localLibrary
        }
    }

    @ViewBuilder
    private var localLibrary: some View {
        if audio.localFiles.tracks.isEmpty {
            empty(audio.localFiles.unavailableReason ?? "No files yet.")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(audio.localFiles.tracks) { track in
                        row(title: track.title, subtitle: nil) {
                            audio.send(.switchTo(.localFiles))
                            audio.localFiles.play(track)
                            audio.send(.play)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appleMusicLibrary: some View {
        if audio.appleMusic.isAvailable {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(audio.appleMusic.tracks) { track in
                        row(title: track.title, subtitle: track.artist) {
                            audio.send(.switchTo(.appleMusic))
                            audio.appleMusic.play(track)
                            audio.send(.play)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Text(audio.appleMusic.unavailableReason ?? "")
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Allow access") {
                    Task { await audio.appleMusic.requestAccess() }
                }
                .font(DashFont.label())
                .foregroundStyle(theme.background)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(theme.accent, in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var drivingView: some View {
        VStack(spacing: 6) {
            Text(audio.state.item?.title ?? "Nothing playing")
                .font(DashFont.value(18))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            if let artist = audio.state.item?.artist {
                Text(artist)
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            TransportControls(audio: audio, size: 52)
            Text("Browsing is off while you're moving")
                .font(DashFont.label(10))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DashFont.label(14))
                    .foregroundStyle(theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(DashFont.label(11))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(theme.tile.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .font(DashFont.label(12))
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
