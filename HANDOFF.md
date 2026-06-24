# Autocrate — Session Handoff (2026-06-24, session 2)

> For the next Claude Code session. Supersedes the original freeze-focused handoff (that bug is
> fixed). Two branches of work landed; a DSP migration is mid-flight. Everything below is current.

---

## TL;DR

- **Three bugs fixed** (branch `fix/library-freeze-decode-streaming`, **pushed**): library-read freeze,
  GetSongBPM no-result decode crash, dead-looking panel (now streams).
- **DSP migration started** (branch `feat/preview-dsp`, **pushed, NOT merged**): replacing GetSongBPM
  with on-device DSP of Apple's 30s preview clips. **Phase 0 + Phase 1a/1b done + tempo upgrade.**
  69 tests green.
- **NEXT: Phase 1c (HybridFeatureProvider) + Phase 2 (wire into the app).** Precise steps below.
- Plan doc: `docs/superpowers/plans/2026-06-24-preview-dsp-features.md` — READ IT FIRST.

---

## Why the DSP migration exists (don't re-derive)

GetSongBPM's catalog barely covers this user's library. Empirically: a sweep of 80 electronic
library tracks found **3, missed 77**; even **Skrillex – Bangarang** (clean query) misses. Apple
Music has **no local BPM tags** (0 of 1932). So the only full-coverage feature source is **on-device
DSP of Apple's free, DRM-free ~30s preview clips** (iTunes Search API `previewUrl`).

**Spike + Phase 0 gate proved:**
- **Key/Camelot detection is reliable** on 30s clips (Strobe→1A conf 0.86, Hotel California→10B conf
  0.84 — both exact). This is the core of harmonic mixing. ✅
- **BPM has a ceiling.** A preview that lacks the main beat (e.g. Strobe's ambient intro) yields a
  confident WRONG BPM — autocorrelation peak strength ≠ correctness. BPM is **best-effort only**.

**DECISION (locked): HYBRID, key-dominant.** Camelot always from DSP (full coverage). BPM from
GetSongBPM where it has the track; DSP-BPM only when confident; else nil. Rank key first.

---

## Branch / git state

- Default branch `main` — behind; neither feature branch merged.
- `fix/library-freeze-decode-streaming` (pushed): freeze + decode + streaming fixes, the plan doc,
  `autocrate-probe`. PR: https://github.com/okku007/autocrate/pull/new/fix/library-freeze-decode-streaming
- `feat/preview-dsp` (pushed, **branched off the fix branch**): all DSP work. **Work here.**
- **`Sources/AutocrateAppKit/Secrets.swift` is modified in the working tree with the REAL API key
  (32 hex chars). NEVER stage/commit it.** HEAD holds the placeholder (`REPLAC…`).
  Verify before any push: `git show HEAD:Sources/AutocrateAppKit/Secrets.swift | grep getSongBpmApiKey`.

---

## What exists now on `feat/preview-dsp`

All in `Sources/AutocrateCore/`:
- `DSP/AudioDecoder.swift` — `monoSamples(url:sampleRate:) async throws -> [Float]` (AVFoundation decode→mono→resample).
- `DSP/KeyEstimator.swift` — `estimate(_:sampleRate:) -> (camelot: CamelotKey, confidence: Double)`;
  FFT chromagram (vDSP) + Krumhansl–Schmuckler. Also `chroma(_:sampleRate:)`, `keyFromChroma(_:)`. **Reliable.**
- `DSP/TempoEstimator.swift` — `estimate(_:sampleRate:band:) -> (bpm: Double, confidence: Double)`;
  **spectral-flux** onset + autocorrelation. Best-effort (see ceiling above).
- `Data/iTunesResolver.swift` — `CatalogMatch` now has `previewUrl: URL?`; `parse` extracts it.
- `Data/PreviewDSPProvider.swift` — `FeatureProvider` impl: resolve→`previewUrl`→`PreviewSampleLoader`
  (download+decode, injectable)→KeyEstimator (camelot always) + TempoEstimator (bpm only if
  `confidence >= bpmConfidenceThreshold`, default 0.4). source `"dsp"`.
- `Sources/autocrate-dsp-probe/main.swift` — Phase 0 gate harness (decodes clips, prints BPM/key vs truth).

Tests (TDD, all green, 69 total): `TempoEstimatorTests`, `KeyEstimatorTests`, `AudioDecoderTests`,
`PreviewDSPProviderTests`, plus `ITunesResolverTests` extended.

**Integration seam:** `FeatureProvider` protocol = `func lookup(artist:title:id:) async -> CachedFeature`.
`GetSongBpmClient` and `PreviewDSPProvider` both implement it. `FeatureHydrator(cache:provider:)` takes one.
`MatchEngine.init` currently builds `FeatureHydrator(..., provider: GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey))`.
`CachedFeature` fields: `id,title,artist,bpm:Double?,camelot:String?,musicalKey:String?,source:String,state:LookupState,fetchedAt:Int` (GRDB record; schema in `FeatureCache.swift` migrator).

---

## NEXT STEPS (precise, TDD each)

### Phase 1c — `HybridFeatureProvider` (NEW: `Sources/AutocrateCore/Data/HybridFeatureProvider.swift`)
`FeatureProvider` wrapping `dsp: PreviewDSPProvider` (primary) + `bpmFallback: FeatureProvider`
(GetSongBpmClient). Logic:
```
let f = await dsp.lookup(...)            // camelot always; bpm only if confident
guard f.state == .found else { return f }
if f.bpm == nil {
    let api = await bpmFallback.lookup(...)
    if let apiBpm = api.bpm { return f with bpm = apiBpm, source = "dsp+api" }   // keep DSP camelot
}
return f
```
`CachedFeature` is immutable (`let`) → reconstruct it to swap bpm. TDD with a fake DSP (camelot, bpm nil)
+ fake fallback (bpm 128) → assert merged bpm 128, camelot from DSP, state .found.

### Phase 2 — wire into the app
1. `FeatureCache.swift`: add GRDB **migration v2** adding `confidence` REAL column; add
   `confidence: Double?` to `CachedFeature`; update ALL constructors (GetSongBpmClient,
   PreviewDSPProvider, FakeProvider in `FeatureHydratorTests`). PreviewDSPProvider should store its
   key/tempo confidence.
2. `MatchEngine.init`: replace the provider with
   `HybridFeatureProvider(dsp: PreviewDSPProvider(), bpmFallback: GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey))`.
3. **Cache invalidation:** existing rows have `source == "getsongbpm"` and stale features. Re-fetch rows
   whose `source` isn't a DSP source (don't trust old camelot==nil rows). Do NOT `rm` the sqlite while
   the app is open (corrupts the open connection — known hazard).
4. **Background pre-warm (the latency fix):** DSP is local + unthrottled, so warm the WHOLE library in
   the background (raise/remove `FeatureHydrator.cap`, parallelize clip downloads). After warm, panel
   opens are instant. This is what finally fixes "the song's over before results appear."

### Phase 3 — ranking + cleanup
- `Ranker`/`CandidatePipeline`: weight Camelot relation higher; treat BPM as a soft factor that is
  SKIPPED (not penalized) when nil. Update tests.
- `README.md`: keep the GetSongBPM attribution line while GetSongBPM still ships (it's now a BPM fallback).

---

## Run / verify

```sh
cd /Users/okku/Desktop/Essentials/Projects/autocrate
git checkout feat/preview-dsp
swift test                        # 69 green
swift build && xcodebuild -project Autocrate.xcodeproj -scheme Autocrate -destination 'platform=macOS' -derivedDataPath .xcbuild build
```

**Phase 0 DSP gate needs real preview clips, which were in a SESSION-LOCAL scratchpad that is now
GONE.** Re-download to re-run `autocrate-dsp-probe`:
```sh
mkdir -p /tmp/clips && cd /tmp/clips
for t in "deadmau5 strobe:strobe" "eagles hotel california:hotelcalifornia" "skrillex bangarang:bangarang"; do
  q="${t%%:*}"; name="${t##*:}"
  url=$(curl -s "https://itunes.apple.com/search?term=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$q")&entity=song&limit=1" | python3 -c "import json,sys;print(json.load(sys.stdin)['results'][0]['previewUrl'])")
  curl -s -o "$name.m4a" "$url"
done
cd /Users/okku/Desktop/Essentials/Projects/autocrate && CLIPS=/tmp/clips swift run autocrate-dsp-probe
# Expect: key 2/2 exact (1A, 10B). BPM best-effort (Hotel ~73 ok; Strobe/Bangarang unreliable — known).
```

---

## Gotchas (carry forward)

- **BPM is best-effort, key is the product.** Don't chase perfect BPM from 30s previews — hard ceiling.
  No free BPM API has this genre (GetSongBPM ~4%, Deezer's `bpm` field is 0/unpopulated, AcousticBrainz
  frozen, Soundcharts paid, TuneBat no API). DSP is the best source we have.
- `PreviewDSPProvider.bpmConfidenceThreshold` default 0.4 — TUNABLE; the confidence metric is weak
  (can be high on spurious periodicity). Revisit if doing more tempo work.
- Cache has no TTL; clearing while the app/probe is open corrupts SQLite (`vnode unlinked`). Quit first,
  or `DELETE FROM feature_cache`, or bypass via the probe.
- The user runs the Xcode build (⌘R), not `.xcbuild/`. Rebuild after source changes.
- `MatchEngine.refresh()` now streams (`.preparing` → `.indexing` per yield → `.ready`); reads once per
  panel open (no auto-refresh on track change). Library read is off-main + fast (`readAllAsync`).
