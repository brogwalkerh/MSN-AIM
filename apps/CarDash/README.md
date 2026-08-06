# CarDash

A tileable in-car dashboard for iPhone. One landscape screen, split into panes you
arrange yourself — map, music, gauges, phone, weather — for a phone mounted in a car
that doesn't have CarPlay.

Native SwiftUI, **iOS 26 minimum**. Unrelated to the Electron project in the rest of
this repository; it just shares the repo.

## What this can and cannot be

Worth reading before the setup chores, because one of these is a hard limit and not a
to-do item.

**iOS never lets one app embed or control another app's interface.** There is no API to
put Spotify's or Apple Maps' actual UI inside a tile. Every section here is *our* UI
talking to that service's SDK. That gap is the one thing real CarPlay does that this
cannot, and the app says so in its own onboarding rather than letting it be discovered
at 60 mph.

Concretely:

| Section | What actually works |
|---|---|
| **Map** | Full MapKit map, search, routing, follow-me camera, spoken turn prompts. MapKit supplies route *data* only, so guidance is ours: no lane guidance, junction views, live-traffic ETA or speed limits. A prominent "Open in Apple Maps" button hands off when you want the real thing. |
| **Spotify** | Play/pause/skip/seek, now-playing, artwork, playlists. Needs Premium and the Spotify app installed — playback happens in Spotify's process, not ours. |
| **Apple Music** | Your on-device library, and reading what the system Music app is playing. Catalog browsing/playback is hidden without a subscription rather than upsold. |
| **YouTube** | Foreground playback via the embedded IFrame player. Audio stops when you leave the app or lock the screen; that's YouTube's behaviour, not a bug. |
| **Local files** | Import audio into the app and play it. No account, no network — the one source that always works. |
| **Phone / Messages** | Dial a favourite, and compose a prefilled message that *you* tap send on. iOS forbids reading your inbox, sending silently, or reading the system call history. |
| **Gauges / Weather / Clock** | Speed, heading, altitude, g-force, trip meter, conditions, forecast. No accounts needed. |

**CarPlay itself is out of scope,** even for a car that has it: CarPlay third-party apps
are template-only, so a user-arranged tiling dashboard cannot exist there. No CarPlay
entitlement is requested.

## Layout of this directory

```
CarDash.xcodeproj/     hand-written project file — see the comment at the top of it
Supporting/            Info.plist, entitlements, xcconfigs (referenced by path, not membership)
App/                   the @main shell — a buildable folder, add files freely
AppTests/              app-level tests (simulator only) — also a buildable folder
Scripts/               CI helpers that also run locally
Packages/
  CarDashCore/         Foundation only. Builds and tests on Linux. The layout engine,
                       persistence, playback state machine, guidance engine live here.
  CarDashKit/          SwiftUI + Apple frameworks + Spotify SDK. Everything visual.
```

The split between the two packages is the testing strategy, not taste. This app is
developed on a Linux machine with no macOS and no Xcode, so `CarDashCore` is kept
Foundation-only in order that `swift test` can prove it correct on every push. Anything
that can be a pure function should live there.

`App/` and `AppTests/` are Xcode 16 *buildable folders*: they reference a directory, and
every file inside is compiled automatically. **Adding a Swift file never requires
editing the project file.**

## Running it

```bash
open apps/CarDash/CarDash.xcodeproj
```

Pick the CarDash scheme and a simulator, and press run. Nothing below is needed to get
that far.

The first time you open the project, Xcode will rewrite `project.pbxproj` from XML into
its own format. That is expected — commit the diff and carry on. (If it refuses to open
at all: `brew install xcodegen && cd apps/CarDash && xcodegen generate`, then commit.
See `project.yml`.)

To check the project file without a Mac:

```bash
python3 apps/CarDash/Scripts/validate_project.py
cd apps/CarDash/Packages/CarDashCore && swift test
```

## Setup checklist

None of this blocks the map, gauges, weather, clock, local audio, or the tiling itself.
Do it when you need the section it unlocks.

**On your Mac, once**

1. Xcode → Settings → Accounts → add the Apple ID with your Developer Program membership.
2. `cp Supporting/Secrets.example.xcconfig Supporting/Secrets.xcconfig` and fill in
   `DEVELOPMENT_TEAM`. That file is gitignored, and the build works without it.

**Apple Developer portal** — Certificates, Identifiers & Profiles

3. Create an explicit App ID matching `CARDASH_BUNDLE_ID` in `Supporting/Base.xcconfig`
   (`com.brogwalkerh.cardash`).
4. On that App ID → **App Services** → enable **MusicKit**. Needed before the Apple
   Music section works.
5. On that App ID → **Capabilities** → enable **WeatherKit**. Only needed for the
   WeatherKit provider; the weather section ships on Open-Meteo, which needs nothing.
6. Leave signing on automatic. A paid membership gives one-year provisioning profiles,
   so the app will not expire on you mid-road-trip the way a free account's 7-day
   profile would.

**Spotify** — developer.spotify.com/dashboard

7. Create an app; put its Client ID into `SPOTIFY_CLIENT_ID` in `Secrets.xcconfig`.
8. Redirect URI, exactly: `cardash://spotify-callback`
9. Add the bundle identifier from step 3.
10. Under "which APIs are you planning to use", tick **iOS** and **Web API**.

There is no client secret. The app uses the PKCE flow, which does not need one — and a
secret shipped inside an app is not a secret.

**On the phone**

11. iOS 26 or later.
12. Install Spotify and sign in with the Premium account. The SDK connects to that app;
    it does nothing without it, and it cannot be tested on a simulator.
13. Grant Location ("While Using") and Media & Apple Music on first launch. Contacts is
    never requested — the app uses the picker, which needs no permission.
14. Use a **vented** mount. A phone running maps with the screen pinned on will
    thermally throttle behind glass in the sun, and a throttled iPhone dims itself and
    loses GPS accuracy.

## Verification

There is no Mac in the development loop, so CI is the only oracle
(`.github/workflows/ios.yml`):

- **project-file** — parses the hand-written pbxproj, resolves every internal reference,
  and checks that build settings point at files that exist. Seconds, on Linux.
- **core** — `swift build && swift test` for `CarDashCore` in a Swift container.
- **ios** — `xcodebuild build` and `xcodebuild test` on a pinned `macos-26` runner
  against a simulator resolved by UDID.

Things CI structurally cannot check, and which need a real device: Spotify App Remote
behaviour, GPS and route quality, audio handoff between apps, thermals, and anything
involving the lock screen.
