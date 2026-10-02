# DRIVEVERSE — Development Specification

DriveVerse is a personal iOS app that observes Apple Music playback, fetches
time-synced lyrics, and displays them in the app and through a Live Activity on
the Lock Screen, Dynamic Island, and CarPlay.

Read `TODO.md` before making changes. It is the source of truth for the current
project status and accepted delivery. Earlier plans are archived in
`docs/DEVELOPMENT_HISTORY.md`.

## Product boundaries

- Apple Music is the only playback source.
- Observe and control Apple Music with `MPMusicPlayerController.systemMusicPlayer`.
  Controls are limited to play/pause, previous/next, and seeking.
- Lyrics are lazily searched from Kugou, NetEase, then LRCLIB and cached locally
  for no more than 30 days. Providers conform to `LyricsProvider`; at most three
  candidates per provider are fetched before falling back to the next source.
- The app has no account, analytics, backend, or tracking.
- This is a personal sideloaded app, not an App Store product.
- Do not add a conventional Home Screen or Lock Screen widget. The WidgetKit
  extension exists only because ActivityKit requires it for Live Activity UI.
- Do not add CarPlay templates or request a CarPlay entitlement. CarPlay uses
  the Live Activity presentation.

## Supported platforms and build

- Minimum deployment target: iOS 26.
- Native iPhone and iPad targets.
- Xcode 27 and SwiftUI.
- `project.yml` is the XcodeGen source of truth; the generated
  `DriveVerse.xcodeproj` is not committed.
- GitHub Actions runs the Swift test suite before building and packaging an
  unsigned IPA for AltStore signing.

## Runtime pipeline

```text
Apple Music playback
        │
        ▼
AppleMusicSource
        │
        ├──► SyncEngine ──► in-app lyrics
        │
        └──► LyricsService ──► cache / Kugou → NetEase → LRCLIB
                                  │
                                  ▼
                         Live Activity controller
                                  │
                                  ▼
                   Lock Screen / Dynamic Island / CarPlay
```

`AppleMusicSource` listens for MediaPlayer notifications and also performs a
one-second read while active. `SyncEngine` extrapolates the playback position,
detects seeks, and maps the position to the active lyric line.

## Live Activity rules

- One activity spans the listening session so background track changes remain
  updates instead of requiring a new activity request.
- Classic three-color word highlighting updates when the active word changes,
  with a 0.2 s minimum ordinary update interval. Progressive fill archives
  native animation endpoints; fill, held-word and marquee phases share a
  0.5 s ordinary update interval. Line/track/playback changes and the initial
  fill endpoint send immediately. Unchanged sync ticks do not submit updates.
- Lock-screen held-word enhancement moves the whole provider token together,
  with a 2-point maximum lift. Brightness must remain behind the fill mask;
  expired animation endpoints settle without replaying a glow.
- Keep ActivityKit content below its payload limit.
- Drive Mode uses an explicit, low-accuracy background location session to
  keep personal sideloaded builds alive while driving. Location values are
  discarded and never stored or transmitted.

## Lyrics model and presentation

- `LyricsDocument` is the cached provider-neutral representation. Its cache
  key includes the provider and format version.
- Each `LyricsLine` preserves immutable original text and can also carry a
  translation, transliteration, start/end timing, and optional word timing.
- Transliteration and Simplified/Traditional Chinese conversion are
  presentation-only operations. Never write their output over original text.
- The default presentation is original plus translation. Transliteration is
  opt-in, and a global ±5 second timing offset is available in Settings.
- UI language follows the system, with Simplified Chinese, Traditional Chinese,
  and English fallback. UI strings live in `Localizable.xcstrings`, privacy
  prompts in `InfoPlist.xcstrings`, and shortcut phrases in
  `AppShortcuts.xcstrings`.

## Verification

- Keep pure parsing, matching, caching, sync, and update-policy logic covered by
  unit tests.
- Run `./scripts/test.sh` on macOS.
- The GitHub Actions build must embed `DriveVerseWidgets.appex`, support both
  iPhone and iPad, and produce `DriveVerse-unsigned.ipa`.
- MediaPlayer, background execution, Dynamic Island, and CarPlay behavior need
  real-device verification.
