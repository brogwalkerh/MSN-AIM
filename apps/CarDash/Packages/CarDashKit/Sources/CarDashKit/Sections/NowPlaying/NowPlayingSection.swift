import SwiftUI
import CarDashCore

enum NowPlayingSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .nowPlaying,
            title: "Now Playing",
            systemImage: "waveform",
            blurb: "A compact transport bar for whatever this app is playing.",
            capabilities: [.singleton]
        ) { context in
            AnyView(NowPlayingPaneView(context: context))
        }
    }
}

struct NowPlayingPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme

    private var audio: AudioCoordinator { context.services.audio }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(audio.state.item?.title ?? "Nothing playing")
                    .font(DashFont.value(context.environment.isCompact ? 15 : 18))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                if let artist = audio.state.item?.artist {
                    Text(artist)
                        .font(DashFont.label(11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                } else if let provider = audio.state.activeProvider {
                    Text(provider.displayName)
                        .font(DashFont.label(11))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TransportControls(audio: audio, size: context.environment.isCompact ? 40 : 48)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Play/pause and skip, sized for a moving car.
///
/// Note what is *not* here: this bar drives whatever this app is playing. It cannot show
/// or control audio from another app that this app did not start — iOS gives no way to
/// read another process's playback. When Spotify is the source it is being driven
/// through its own SDK, which is a different thing from observing it.
struct TransportControls: View {
    let audio: AudioCoordinator
    var size: CGFloat = 48

    @Environment(\.dashTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            button("backward.fill", label: "Previous") { audio.send(.previous) }
            button(
                audio.state.isPlaying ? "pause.fill" : "play.fill",
                label: audio.state.isPlaying ? "Pause" : "Play",
                prominent: true
            ) {
                audio.send(.toggle)
            }
            button("forward.fill", label: "Next") { audio.send(.next) }
        }
        .disabled(audio.state.activeProvider == nil)
        .opacity(audio.state.activeProvider == nil ? 0.4 : 1)
    }

    private func button(
        _ systemImage: String,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(prominent ? theme.background : theme.primaryText)
                .frame(width: size, height: size)
                .background(prominent ? theme.accent : theme.tile, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
