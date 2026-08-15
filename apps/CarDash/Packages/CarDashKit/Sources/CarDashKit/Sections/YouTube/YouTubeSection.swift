import SwiftUI
import UIKit
import WebKit
import CarDashCore

enum YouTubeSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .youtube,
            title: "YouTube",
            systemImage: "play.rectangle.fill",
            blurb: "Foreground only — audio stops when you leave the app.",
            capabilities: [.producesAudio, .needsNetwork, .singleton]
        ) { context in
            AnyView(YouTubePaneView(context: context))
        }
    }
}

/// Hosts the provider's web view.
///
/// The view is *not* created here. It belongs to the provider, so that being re-laid out — which
/// happens on every divider drag — does not reload the page and restart the video.
struct YouTubePlayerView: UIViewRepresentable {
    let player: YouTubeWebPlayer

    func makeUIView(context: Context) -> WKWebView { player.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct YouTubePaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var pasteFailed = false

    private var youtube: YouTubeProvider { context.services.audio.youtube }
    private var audio: AudioCoordinator { context.services.audio }
    private var isDriving: Bool { context.services.location.isDriving }

    var body: some View {
        VStack(spacing: 6) {
            if youtube.current != nil {
                nowPlaying
            } else {
                chooser
            }
        }
        .panePadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole reason this tile is honest about being a parked-car feature. The app holds
        // the audio background mode for its own files and could keep playing; YouTube's terms
        // say not to.
        .onChange(of: scenePhase) { _, phase in
            youtube.setForeground(phase == .active)
        }
    }

    // MARK: - Playing

    private var nowPlaying: some View {
        VStack(spacing: 4) {
            ZStack {
                YouTubePlayerView(player: youtube.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Blocking touches while moving stops a driver poking at an embedded web
                // player. The transport buttons below still work.
                if isDriving {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                }
            }

            if let error = youtube.lastError {
                problem(error)
            } else if !context.environment.isCompact {
                Text(youtube.current?.displayTitle ?? "")
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                TransportControls(audio: audio, size: isDriving ? 52 : 40)
                Button {
                    audio.send(.switchTo(.youtube))
                    youtube.relinquish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(theme.tile, in: Circle())
                        .foregroundStyle(theme.primaryText)
                }
                .accessibilityLabel("Stop and choose something else")
            }
        }
    }

    private func problem(_ message: String) -> some View {
        VStack(spacing: 4) {
            Text(message)
                .font(DashFont.label(11))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Some videos genuinely cannot play outside YouTube — the owner disallows
            // embedding. Offering the app is the only real answer, rather than a retry that
            // can never work.
            if youtube.needsTheApp, let url = youtube.currentVideoURL {
                Button("Open in YouTube") {
                    UIApplication.shared.open(url)
                }
                .font(DashFont.label(12))
                .foregroundStyle(theme.accent)
            }
        }
    }

    // MARK: - Choosing

    @ViewBuilder
    private var chooser: some View {
        if isDriving {
            Text("Pick something before you set off.")
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                pasteButton

                if youtube.recents.isEmpty {
                    VStack(spacing: 4) {
                        Text("Copy a YouTube link, then tap Paste.")
                            .font(DashFont.label(12))
                            .foregroundStyle(theme.secondaryText)
                        // Said plainly here rather than discovered on the motorway.
                        Text("Audio stops when you leave the app or lock the screen — YouTube doesn't allow background playback.")
                            .font(DashFont.label(10))
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    recentsList
                }
            }
        }
    }

    private var pasteButton: some View {
        HStack(spacing: 6) {
            // There is no search, deliberately: searching means typing, and this tile refuses
            // to show a list at all once the car is moving.
            Button {
                paste()
            } label: {
                Label("Paste a link", systemImage: "doc.on.clipboard")
                    .font(DashFont.label(12))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(theme.tile, in: Capsule())
                    .foregroundStyle(theme.primaryText)
            }

            Spacer(minLength: 0)

            if pasteFailed || youtube.lastError != nil {
                Text(youtube.lastError ?? "Nothing to paste.")
                    .font(DashFont.label(10))
                    .foregroundStyle(theme.destructive)
                    .lineLimit(1)
            }
        }
    }

    private var recentsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(youtube.recents.videos) { video in
                    Button {
                        audio.send(.switchTo(.youtube))
                        youtube.play(video)
                        audio.send(.play)
                    } label: {
                        HStack(spacing: 8) {
                            AsyncImage(url: video.thumbnailURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(theme.tile)
                            }
                            .frame(width: 48, height: 27)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(video.displayTitle)
                                .font(DashFont.label(13))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 42)
                        .background(theme.tile.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    // A context menu, not `.swipeActions` — that modifier only does anything
                    // inside a List, and this is a LazyVStack in a ScrollView.
                    .contextMenu {
                        Button(role: .destructive) {
                            youtube.remove(video.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            pasteFailed = true
            return
        }
        pasteFailed = false
        if youtube.add(fromPastedText: text) {
            audio.send(.switchTo(.youtube))
            audio.send(.play)
        }
    }
}
