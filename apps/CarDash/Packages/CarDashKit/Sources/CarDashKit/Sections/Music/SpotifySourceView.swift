import SwiftUI
import UIKit
import CarDashCore

/// The Spotify half of the Music tile.
///
/// Four states, all of them ordinary: no client ID configured, signed out, signed in with
/// nowhere to play, and signed in with a library. The third is the one worth care — a
/// phone that has just been mounted has no active Spotify device, and Spotify says so with
/// a 404. Presented as an error, that reads as a broken app on every first use of the day.
struct SpotifySourceView: View {
    let provider: SpotifyProvider
    let audio: AudioCoordinator

    @Environment(\.dashTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .playlists

    private enum Tab: String, CaseIterable {
        case playlists = "Playlists"
        case recent = "Recent"
    }

    var body: some View {
        Group {
            switch provider.auth.state {
            case .notConfigured:
                message(provider.unavailableReason ?? "", action: nil)
            case .signedOut, .failed:
                signInPrompt
            case .authorizing:
                ProgressView().tint(theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedIn:
                signedIn
            }
        }
        .task {
            provider.setVisibility(tileVisible: true, foreground: true)
            if provider.isSignedIn, provider.playlists.isEmpty {
                await provider.loadLibrary()
            }
        }
        .onDisappear {
            provider.setVisibility(tileVisible: false)
        }
        .onChange(of: scenePhase) { _, phase in
            provider.setVisibility(foreground: phase == .active)
        }
    }

    // MARK: - States

    private var signInPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondaryText)
            Text(provider.auth.state == .signedOut
                 ? "Connect Spotify to play your playlists here."
                 : provider.unavailableReason ?? "")
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Connect Spotify") {
                Task { await provider.signIn() }
            }
            .font(DashFont.label())
            .foregroundStyle(theme.background)
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(theme.accent, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var signedIn: some View {
        VStack(spacing: 6) {
            if provider.needsDevice {
                devicePicker
            }
            if let error = provider.lastError {
                Text(error)
                    .font(DashFont.label(11))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .playlists: playlistList
            case .recent: recentList
            }
        }
    }

    // Spotify will not start playing on a device it does not already consider active, so
    // this is a prerequisite rather than a nicety. "Play on this iPhone" only appears when
    // Spotify can actually see the phone, which means the Spotify app has run at least
    // once since the last reboot.
    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing is playing on any Spotify device.")
                .font(DashFont.label(11))
                .foregroundStyle(theme.secondaryText)

            if provider.devices.isEmpty {
                Button("Open Spotify") {
                    if let url = URL(string: "spotify:") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(DashFont.label(12))
                .foregroundStyle(theme.accent)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(provider.devices.filter { $0.isControllable }) { device in
                            Button {
                                Task { await provider.transfer(to: device) }
                            } label: {
                                Text(device.looksLikeThisPhone ? "Play on this iPhone" : device.name)
                                    .font(DashFont.label(12))
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(theme.tile, in: Capsule())
                                    .foregroundStyle(theme.primaryText)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playlistList: some View {
        if provider.isLoadingLibrary && provider.playlists.isEmpty {
            ProgressView().tint(theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if provider.playlists.isEmpty {
            message("No playlists yet.") {
                Task { await provider.loadLibrary() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(provider.playlists) { playlist in
                        row(
                            title: playlist.name,
                            subtitle: playlist.trackCount > 0 ? "\(playlist.trackCount) tracks" : playlist.owner,
                            artwork: playlist.artworkURL
                        ) {
                            audio.send(.switchTo(.spotify))
                            Task { await provider.play(playlist) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentList: some View {
        if provider.recent.isEmpty {
            message("Nothing played recently.") {
                Task { await provider.loadLibrary() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(provider.recent) { track in
                        row(
                            title: track.item.title,
                            subtitle: track.item.artist,
                            artwork: track.item.artworkURL
                        ) {
                            audio.send(.switchTo(.spotify))
                            Task { await provider.play(track) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func row(
        title: String,
        subtitle: String?,
        artwork: URL?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AsyncImage(url: artwork) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(theme.tile)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))

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
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(theme.tile.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func message(_ text: String, action: (() -> Void)?) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            if let action {
                Button("Refresh", action: action)
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
