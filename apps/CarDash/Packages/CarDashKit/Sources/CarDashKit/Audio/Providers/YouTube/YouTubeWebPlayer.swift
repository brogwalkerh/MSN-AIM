import SwiftUI
import UIKit
import WebKit
import CarDashCore
import os

/// The YouTube IFrame player, in a web view.
///
/// **Why a web view rather than extracting a stream.** YouTube's terms require embedded playback
/// to go through their own player, which shows their ads and counts their views. Pulling the
/// media URL out and handing it to `AVPlayer` would give a nicer tile, background audio and
/// lock-screen controls — and would be a straightforward terms violation that stops working the
/// day they change something. So: the IFrame API, with the limitations that come with it.
///
/// **What those limitations cost.** Audio comes out of this web view, in this app's process,
/// which is why `ProviderID.youtube.ownsAudioSession` is true. But the same terms forbid
/// background playback, so the tile deliberately pauses when the app leaves the foreground —
/// even though the app holds the `audio` background mode for its own local files and could
/// technically keep going. That makes this a parked-car tile, and the UI says so rather than
/// leaving the driver to discover it at 70mph.
@MainActor
final class YouTubeWebPlayer: NSObject {
    /// Events from the JavaScript side.
    var onEvent: ((YouTubePlayerEvent) -> Void)?

    private(set) lazy var webView: WKWebView = makeWebView()
    private var isReady = false
    /// Commands that arrived before the player finished loading. Dropping them instead would
    /// mean the first tap after opening the tile silently does nothing.
    private var pending: [String] = []
    private static let log = Logger(subsystem: "dev.cardash", category: "youtube")

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Without this the video takes over the whole screen the moment it plays, which on a
        // tiled dashboard is exactly wrong.
        configuration.allowsInlineMediaPlayback = true
        // The user already tapped a video in our list; making them tap again inside the web
        // view would be a second gesture for the same intent.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(Bridge(player: self), name: "cardash")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    // MARK: - Loading

    func load(_ video: YouTubeVideo) {
        isReady = false
        pending.removeAll()
        // `about:blank` as the base URL would make the IFrame API refuse to load; it checks the
        // origin against the `origin` parameter it is given.
        webView.loadHTMLString(Self.html(for: video), baseURL: URL(string: "https://www.youtube.com"))
    }

    func play() { evaluate("player.playVideo();") }
    func pause() { evaluate("player.pauseVideo();") }
    func seek(to seconds: TimeInterval) { evaluate("player.seekTo(\(max(0, seconds)), true);") }

    /// Stops playback and tears the page down.
    ///
    /// Loading a blank page rather than only pausing: a paused YouTube player left in a web view
    /// keeps a media session alive, and iOS will show it in the lock-screen controls competing
    /// with whatever the user switched to.
    func stop() {
        isReady = false
        pending.removeAll()
        webView.loadHTMLString("<html><body style='background:transparent'></body></html>", baseURL: nil)
    }

    private func evaluate(_ script: String) {
        guard isReady else {
            pending.append(script)
            return
        }
        webView.evaluateJavaScript(script) { _, error in
            if let error { Self.log.debug("player script failed: \(error)") }
        }
    }

    private func flushPending() {
        let queued = pending
        pending.removeAll()
        for script in queued { evaluate(script) }
    }

    // MARK: - The page
    //
    // Deliberately tiny and local. A remote page would mean the tile stops working without a
    // signal, and this way there is nothing to load but the API itself.

    private static func html(for video: YouTubeVideo) -> String {
        """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
            <style>
              html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
              #player { position: absolute; inset: 0; width: 100%; height: 100%; }
            </style>
          </head>
          <body>
            <div id="player"></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
              var player;
              var ticker;

              function send(kind, value) {
                window.webkit.messageHandlers.cardash.postMessage({ kind: kind, value: value });
              }

              function onYouTubeIframeAPIReady() {
                player = new YT.Player('player', {
                  videoId: '\(video.id)',
                  playerVars: {
                    playsinline: 1,
                    start: \(video.startSeconds),
                    rel: 0,
                    modestbranding: 1
                  },
                  events: {
                    onReady: onReady,
                    onStateChange: function (event) { send('state', event.data); },
                    onError: function (event) { send('error', event.data); }
                  }
                });
              }

              function onReady() {
                send('ready', 1);
                var data = player.getVideoData();
                if (data && data.title) { send('title', data.title); }
                send('duration', player.getDuration());

                // Position is polled rather than pushed: the IFrame API has no time-update
                // event, and one second is fine for a progress bar glanced at from a mount.
                clearInterval(ticker);
                ticker = setInterval(function () {
                  if (player && player.getCurrentTime) {
                    send('position', player.getCurrentTime());
                  }
                }, 1000);
              }
            </script>
          </body>
        </html>
        """
    }

    /// Holds the player weakly.
    ///
    /// `WKUserContentController` retains its handlers, and the handler retaining the player
    /// which owns the web view which owns the controller is a cycle that leaks a live web view
    /// per tile — with its audio still going.
    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var player: YouTubeWebPlayer?

        init(player: YouTubeWebPlayer) {
            self.player = player
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated {
                guard let player else { return }

                if payload["kind"] as? String == "ready" {
                    player.isReady = true
                    player.flushPending()
                    return
                }
                if let event = YouTubePlayerEvent.decode(payload) {
                    player.onEvent?(event)
                }
            }
        }
    }
}

extension YouTubeWebPlayer: WKNavigationDelegate {
    /// Keeps the web view on YouTube's player and nothing else.
    ///
    /// Without this, tapping the video title or a suggested video navigates the tile to the full
    /// YouTube site, which is a browser inside a dashboard — unusable while driving and not what
    /// anyone asked for. Those taps open the real app instead.
    /// Main-actor isolated, inherited from the class. It was `nonisolated` at first, which
    /// compiles and then warns: `WKNavigationAction`'s own properties are main-actor isolated,
    /// so reading `navigationType` from a nonisolated context is exactly the thing Swift 6
    /// concurrency exists to catch.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        UIApplication.shared.open(url)
    }
}
