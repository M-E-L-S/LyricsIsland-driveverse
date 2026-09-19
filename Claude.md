# DRIVEVERSE — Development Specification

DriveVerse is a personal iOS app that observes Apple Music playback, fetches
time-synced lyrics, and displays them in the app and through a Live Activity on
the Lock Screen, Dynamic Island, and CarPlay.

Read `TODO.md` before making changes. It is the source of truth for the current
roadmap and completed phases.

## Product boundaries

- Apple Music is the only playback source.
- Observe playback with `MPMusicPlayerController.systemMusicPlayer`; the app
  does not play or control music.
- Lyrics are currently fetched from LRCLIB and cached locally for no more than
  30 days. Additional lyric providers must conform to the provider architecture
  planned in `TODO.md`.
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
        └──► LyricsService ──► cache / LRCLIB
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
- Update ActivityKit only when the track, lyric line, or play/pause state
  changes. Do not update on every sync tick.
- Keep ActivityKit content below its payload limit.
- Drive Mode uses an explicit, low-accuracy background location session to
  keep personal sideloaded builds alive while driving. Location values are
  discarded and never stored or transmitted.

## Lyrics direction (planned in P3)

- Preserve original lyric text. Never irreversibly replace Chinese or other
  scripts with Latin transliteration.
- The planned unified model supports original text, translation,
  transliteration, line timing, and optional word timing.
- UI language follows the system, with Simplified Chinese, Traditional Chinese,
  and English fallback planned in `TODO.md`.

## Verification

- Keep pure parsing, matching, caching, sync, and update-policy logic covered by
  unit tests.
- Run `./scripts/test.sh` on macOS.
- The GitHub Actions build must embed `DriveVerseWidgets.appex`, support both
  iPhone and iPad, and produce `DriveVerse-unsigned.ipa`.
- MediaPlayer, background execution, Dynamic Island, and CarPlay behavior need
  real-device verification.
