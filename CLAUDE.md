# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Autocrate is a native macOS menu-bar utility for Apple Music. It reads the now-playing track as a
seed, derives its tempo (BPM) and key (Camelot), and surfaces a ranked shortlist of harmonically- and
tempo-compatible tracks to play next. It does **not** mix — Apple Music's AutoMix handles playback;
Autocrate curates the setlist. v1 is show-only.

## Build & test

```sh
swift test                              # AutocrateCore unit tests (all logic lives here)
swift test --filter RankerTests         # single test class
swift test --filter RankerTests/testExactBeatsShifted   # single test method
swift build                             # both library targets + both probes
xcodegen generate                       # regenerate Autocrate.xcodeproj from project.yml
```

- The shipping app is built/run from **Xcode (⌘R)**, not the CLI — it needs an app bundle, Info.plist,
  bundled fonts, and a TCC Automation entitlement. The user runs this, not you. See `App/README.md`.
- `swift build` / `swift test` cover everything headlessly. Prefer them for verification.
- `.xcbuild/` is a side artifact from an `xcodebuild` invocation; the user's real run is Xcode's ⌘R.
  Rebuild after source changes.

### Probes (executable targets, not shipped)

```sh
swift run autocrate-scan                # whole-library DSP scan → warms features.sqlite (run before the app)
swift run autocrate-probe               # exercises the live ScriptingBridge + pipeline path, times each stage
CLIPS=/tmp/clips swift run autocrate-dsp-probe   # DSP gate: runs estimators vs known clips, prints BPM/key
```

## Architecture

Three layers, split so all the logic is testable without a GUI:

- **`AutocrateCore`** (SwiftPM lib, pure + headlessly tested) — matching logic, feature cache,
  network/DSP feature providers, and the filter+rank pipeline. No AppKit/UI.
- **`AutocrateAppKit`** (SwiftPM lib) — ScriptingBridge readers (`NowPlayingReader`, `LibraryReader`),
  the `MatchEngine` coordinator, SwiftUI panel, theme. Compile-checked headlessly.
- **`App/` + `Autocrate.xcodeproj`** — thin `@main` + Info.plist shell that links `AutocrateAppKit`.

### The data flow (read `MatchEngine.refresh()` to see it whole)

now-playing seed → **hydrate** seed features → read library pool (genre-allowlisted) → **stream
hydrate** the pool → **filter+rank** (`CandidatePipeline` → `Ranker`) → **discover** beyond the library
→ a single `PanelState`. `refresh()` is a state machine that emits intermediate `PanelState`s
(`.preparing` → `.indexing(...)` per progressive yield → `.ready`) so the panel never looks dead.

### Feature provision (the swappable seam)

`FeatureProvider` (`func lookup(artist:title:id:) async -> CachedFeature`) is the abstraction. It
**always** returns a `CachedFeature` (state `.found` or `.miss`) so `FeatureHydrator` can persist every
outcome — each track is fetched at most once. Implementations:

- `GetSongBpmClient` — network BPM/key lookup. Catalog coverage of this user's electronic library is
  poor (~4%); kept as a BPM fallback / discover source.
- `PreviewDSPProvider` — on-device DSP of Apple's free 30s preview clips (resolve `previewUrl` via
  `iTunesResolver` → `PreviewSampleLoader` download/decode → `KeyEstimator` + `TempoEstimator`).
  **Key/Camelot is reliable and full-coverage; BPM is best-effort** (kept only above a confidence
  threshold, else nil). This is the migration in flight — see `HANDOFF.md`.

`FeatureHydrator` is an actor: cache-first, capped per call, throttled, with a progressive
`AsyncStream` variant for live UI. `FeatureCache` is GRDB/SQLite, no TTL (BPM/key are immutable);
schema lives in its `DatabaseMigrator`.

### Matching (pure, in `Matching/`)

- `CamelotWheel.relation` — harmonic compatibility: perfect > relative > adjacent; incompatible → nil.
  Energy-boost and diagonal moves deliberately excluded in v1.
- `BpmBand.evaluate` — ±6% band, with half/double-time matches flagged `tempoShifted`; out of band → nil.
- `Ranker` — Camelot weight dominates; BPM closeness breaks ties; exact tempo beats tempo-shifted.

`CandidatePipeline.shortlist` gates library candidates on a genre allowlist + BPM + Camelot;
`shortlistDiscover` skips the genre gate (discover candidates carry no library genre tag).

## Conventions & gotchas

- **TDD is the workflow here** — every Core type has a matching `Tests/AutocrateCoreTests/*Tests.swift`.
  Write/extend the test first.
- **`Sources/AutocrateAppKit/Secrets.swift` holds the GetSongBPM API key.** HEAD must keep the
  placeholder; the real key lives only in the working tree. **Never stage or commit the real key.**
  Verify before any push: `git show HEAD:Sources/AutocrateAppKit/Secrets.swift | grep getSongBpmApiKey`.
- **Never `rm` the SQLite cache (`~/Library/Application Support/Autocrate/features.sqlite`) while the
  app or a probe is open** — it corrupts the open connection (`vnode unlinked`). Quit first, or
  `DELETE FROM feature_cache`.
- `CachedFeature` is immutable (all `let`) — reconstruct it to change a field.
- Live-API glue (`GetSongBpmClient`, `iTunesResolver`) carries `NOTE:` comments flagging JSON
  field-name assumptions to confirm against a real response.

## Docs

- Current work state / next steps: `HANDOFF.md` (read first when resuming).
- Spec: `docs/superpowers/specs/2026-06-24-autocrate-v1-design.md`
- Plans: `docs/superpowers/plans/2026-06-24-autocrate-v1.md`,
  `docs/superpowers/plans/2026-06-24-preview-dsp-features.md`
