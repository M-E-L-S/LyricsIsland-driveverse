<p align="center">
  <img src="assets/app-icon-rounded.png" alt="DriveVerse app icon" width="112">
</p>

<h1 align="center">DriveVerse</h1>

<p align="center"><strong>Live, time-synced Apple Music lyrics on your iPhone, iPad, and CarPlay screen.</strong></p>

<p align="center">
  <img src="assets/demo.gif" alt="DriveVerse showing synced lyrics advancing on the iPhone lock screen" width="300">
</p>

<p align="center"><em>Lyrics advancing live on the lock screen. The same Live Activity mirrors onto CarPlay on iOS 26. (<a href="assets/demo.mp4">watch the clip</a>)</em></p>

DriveVerse watches the song playing in Apple Music, finds the synced lyrics for it, and shows the current line (plus the one coming up) right on your CarPlay display, lock screen, and Dynamic Island. You keep using Apple Music exactly as usual. DriveVerse just rides along and puts the words on screen.

It doesn't play any music of its own, it isn't a full CarPlay app, and it never touches your playback. It only reads what's playing and shows the lyrics.

Lyrics always keep their original script. When available, translations appear underneath; optional on-device transliteration can be enabled in Settings without modifying the stored original.

> **A note on lyrics and copyright.** Lyrics come from [LRCLIB](https://lrclib.net), a free community lyrics database. That's fine for a personal app you build and run yourself, which is exactly what this is. It is *not* okay for the App Store without a proper licensed lyrics provider, so please don't ship it there. Lyrics are cached only on your device, for 30 days at most.

---

## What it does

- **Reads your current song** from Apple Music through the local MediaPlayer framework.
- **Fetches synced (LRC) lyrics** from LRCLIB and keeps them lined up with the music as it plays.
- **Shows the current line plus its translation or the next line** as a Live Activity — the same tile appears on your **CarPlay** screen, **lock screen**, and **Dynamic Island** on iOS 26.
- **Preserves original lyrics** with optional translation, transliteration, Simplified/Traditional Chinese conversion, and timing offset controls.
- **Keeps working while you drive** through a "Drive Mode" that stops iOS from freezing the app in your pocket.
- **A full-screen scrolling lyrics view** in the app itself, for passengers or when you're parked.
- **Follows the system language** with Simplified Chinese, Traditional Chinese, and English fallback.

No account to make, no server, no analytics, no tracking. Everything happens on your phone.

## How it works

```
Apple Music ──(MediaPlayer, ~1s)──► sync engine ─► lyrics on screen
                                         │                 │
                                         ▼                 ▼
                                LRCLIB lyrics lookup  Live Activity
                                (cached 30 days)      (CarPlay / lock screen / Dynamic Island)
```

A few details worth knowing:

- **Staying in sync:** between updates, the app estimates the current playback position and finds the matching lyric line. If you skip or seek, it notices and snaps to the right line.
- **CarPlay:** iOS 26 automatically mirrors the lock-screen Live Activity onto the car screen. There's no CarPlay entitlement and no CPTemplate code here — the Live Activity *is* the CarPlay experience.

## Requirements

- An iPhone or iPad running **iOS 26 or later** (Apple Music detection and Live Activities need real hardware — the Simulator can't fully test them).
- **Xcode 27** to build it locally.
- A free or paid Apple Developer account to sign the app onto your phone.

## Setup

### 1. Get the code and open it

```bash
git clone https://github.com/M-E-L-S/LyricsIsland-driveverse.git
cd LyricsIsland-driveverse
```

`DriveVerse.xcodeproj` is generated from `project.yml` and is intentionally not checked in. On a Mac, install XcodeGen and generate it before opening the project:

```bash
brew install xcodegen
./scripts/generate.sh
open DriveVerse.xcodeproj
```

When working from Windows, push the source to GitHub instead. The included GitHub Actions workflow runs the unit tests with Xcode 27, generates the project, builds an unsigned iPhone/iPad app with its Live Activity extension, and uploads `DriveVerse-unsigned.ipa`. Download that artifact and sign it with AltStore.

### 2. Sign and run

For a local Mac build, open the generated project in Xcode, pick the **DriveVerse** scheme, and set your signing team on both the `DriveVerse` and `DriveVerseWidgets` targets (Signing & Capabilities tab). Plug in your iPhone or iPad and hit Run.

The fork currently uses `io.github.mels.driveverse`. If signing reports that the identifier is unavailable to your team, edit `project.yml` and replace it with identifiers you control. The Live Activity extension identifier must remain a child of the app identifier:

```yaml
bundleIdPrefix: com.yourname                                 # options
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.driveverse           # DriveVerse target
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.driveverse.widgets   # DriveVerseWidgets target
```

Then regenerate the project or push the change and let GitHub Actions generate it.

### 3. First-launch permissions

- **Media & Apple Music** — needed to see what Apple Music is playing.
- **Live Activities** — turn on **More Frequent Updates** under Settings → DriveVerse → Live Activities, or the lyrics stop updating after about 30 seconds in the background.
- **Location (While Using)** — asked the first time you turn on Drive Mode. It's how the app stays awake in the background (explained below). Say yes to the "Always" upgrade later only if you want the hands-free CarPlay automation.

## Using it in the car

1. Connect your phone to CarPlay and play something in Apple Music.
2. Open DriveVerse and turn on **Drive Mode**.
3. When a song with synced lyrics plays, the lyrics tile shows up on the car screen (and your lock screen and Dynamic Island).

### Turn it on automatically when you get in

You don't have to open the app every time. DriveVerse includes two Shortcuts actions — **Start Drive Mode** and **Stop Drive Mode** — so your phone can do it for you:

1. Open the **Shortcuts** app → **Automation** → **+**.
2. Pick **CarPlay** → **Connects** → **Run Immediately** → add the **Start Drive Mode** action.
3. Make a second one: **CarPlay** → **Disconnects** → **Run Immediately** → **Stop Drive Mode**.

Now getting in the car starts DriveVerse in the background and puts up the lyrics tile on its own (it shows "♪ Waiting for music…" until you press play). Leaving the car shuts it all down so nothing keeps running in the background.

### Why Drive Mode needs to exist

iOS freezes apps a few seconds after you lock the phone or switch away, which would freeze the lyrics too. Drive Mode keeps DriveVerse running using a very low-power background location session (rough, city-block-level accuracy — the location is thrown away instantly and never stored or sent anywhere).

Why location and not the old "play silent audio" trick? Because iOS specifically blocks apps from updating Live Activities when the only reason they're awake is playing background audio. A location session is the same approach navigation apps use, and it's the one that actually lets the lyrics keep updating. It does use some battery, which is why Drive Mode is a manual toggle — and why the CarPlay automation above is handy, since it switches off the moment you leave.

## Privacy

Everything stays on your phone. There's no backend, no account, and no analytics.

- Song info is read locally from Apple Music.
- Only the basic track details (title, artist, album, length) are sent to LRCLIB to look up lyrics.
- Lyrics are cached on disk for up to 30 days. Settings → Clear Cache wipes them.
- Drive Mode's location fixes are discarded immediately — nothing is saved or transmitted.
- Optional lyric transliteration and Simplified/Traditional Chinese conversion happen on the device. No text is sent anywhere for them.

## Running the tests

There's a full unit test suite (Swift Testing). GitHub Actions runs it before packaging the IPA. In Xcode, press **Cmd-U**. From a Mac command line:

```bash
./scripts/test.sh
```

It covers Apple Music state mapping, structured bilingual lyric parsing, title/artist matching, the sync engine, timing offsets, the LRCLIB client and its fallbacks, the versioned on-disk cache, lyric presentation, and the Live Activity update logic.

## Good to know / limitations

- Without Drive Mode on, updates stop shortly after the app goes to the background. That's expected — Drive Mode is the fix.
- DriveVerse can't control playback (it's just watching), so the lyrics view is display-only by design.
- If a song isn't in LRCLIB, you'll see "No lyrics found." Misses are re-checked the next day; hits are cached.
- Optional transliteration uses the standard system transform, which is readable but occasionally a little literal.
- There is no dedicated CarPlay dashboard widget; the Live Activity is the CarPlay experience.

## How the project is organized

```
DriveVerse/
├── App/            App entry point, Drive Mode shortcuts, and the main wiring
├── Core/
│   ├── NowPlaying/ Apple Music playback observation
│   ├── Lyrics/     LRCLIB client, structured model, parser, cache, presentation
│   ├── Sync/       Keeps the lyric line matched to the playback position
│   └── KeepAlive/  Drive Mode background location session
├── LiveActivity/   The lyrics tile shown on CarPlay / lock screen
├── Features/       Home, full-screen lyrics, Settings (SwiftUI)
└── Resources/      Assets and Info.plist
DriveVerseWidgets/  Live Activity + Dynamic Island UI
DriveVerseTests/    The test suite
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Package.swift` is a helper so the core logic can be tested on a Mac without a device.

## Built with

Swift, SwiftUI, ActivityKit, WidgetKit, MediaPlayer, and Core Location. No third-party libraries. Lyrics by [LRCLIB](https://lrclib.net).

## License

The code is released under the [MIT License](LICENSE) — use it, fork it, learn from it. Note that this applies to the app's own code only, not to any song lyrics, which belong to their respective owners and are fetched from LRCLIB for personal use.
