# Autocrate

A native macOS menu-bar utility for heavy Apple Music listeners. It reads the
now-playing track as a seed, looks up its tempo (BPM) and key (Camelot), and
surfaces a ranked shortlist of harmonically- and tempo-compatible tracks to play
next. It doesn't mix — Apple Music's AutoMix handles playback; Autocrate curates
the setlist AutoMix runs on. v1 is show-only: you add picks to your own queue.

## Architecture

- **`AutocrateCore`** (SwiftPM library, headlessly tested) — pure matching logic
  (Camelot wheel, key→Camelot, BPM band with half/double-time, key-dominant ranker),
  GRDB feature cache, the feature providers, lazy/capped/throttled hydrator, and the
  filter+rank pipeline. Features come from a **hybrid provider**: Camelot key from
  on-device DSP of Apple's 30s preview clips (full coverage), with BPM from DSP when
  confident and backfilled from GetSongBPM otherwise.
- **`AutocrateAppKit`** (SwiftPM library) — ScriptingBridge readers, the
  `MatchEngine` coordinator, and the SwiftUI menu-bar panel.
- **`App/` + `Autocrate.xcodeproj`** — the thin macOS app shell (`@main`,
  Info.plist) that links `AutocrateAppKit`.

## Build & test

```sh
swift test          # AutocrateCore unit tests (110)
swift build         # both library targets
xcodegen generate   # regenerate Autocrate.xcodeproj from project.yml
```

## First-time setup (recommended)

Run the library scanner to analyze your whole library on-device and populate the feature cache:

```sh
swift run autocrate-scan
```

It resolves each track's preview clip via iTunes Search and runs on-device DSP for key
(+ best-effort BPM), writing to `~/Library/Application Support/Autocrate/features.sqlite`. A full cold
scan takes ~1.5–2 hrs at iTunes pacing; it is resumable (Ctrl-C anytime; re-run to continue) and
refuses to run while the app is open. Then launch the app with ⌘R.

## Run

Open `Autocrate.xcodeproj` and ⌘R to run. See [`App/README.md`](App/README.md)
for the full Xcode setup (fonts, API key, Automation permission) and the manual
verification checklist.

## Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how Autocrate works end to end: the three layers,
  the now-playing → hydrate → rank → discover pipeline, the panel state machine, and the
  live-follow refresh lifecycle, with diagrams.
- [`App/README.md`](App/README.md) — full Xcode setup (fonts, API key, Automation permission)
  and the manual verification checklist.

## Setup note

Add your free GetSongBPM API key to `Sources/AutocrateAppKit/Secrets.swift`
(replace the placeholder) before running. It's now the **BPM fallback** (and the
discover source); the key always comes from on-device DSP.

---

BPM data provided by [GetSongBPM](https://getsongbpm.com).
