# Preview-Clip DSP Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Status: SCOPING + PHASE 0 GATE.** Phase 0 is a go/no-go prototype. Detailed TDD tasks for
> Phases 1–3 are deliberately written at outline depth because the exact DSP code depends on what
> Phase 0 proves works in Swift. Do **not** flesh Phases 1–3 into step-level tasks until Phase 0
> passes its gate.

**Goal:** Replace GetSongBPM with on-device DSP of Apple's free 30-second preview clips as the
source of BPM + Camelot key, so feature coverage matches the user's actual (electronic) library and
hydration is no longer rate-limited.

**Architecture:** A new `PreviewDSPProvider` implements the existing `FeatureProvider` protocol
(`lookup(artist:title:id:) async -> CachedFeature`), so it drops into `FeatureHydrator` with no
pipeline change. It resolves a track → Apple `previewUrl` (extend `iTunesResolver`), downloads the
~30s AAC clip, decodes it with AVFoundation, and runs Accelerate/vDSP DSP to estimate tempo + key.
Results persist in the existing GRDB `feature_cache` (with a new `confidence` column). Because
analysis is local and unthrottled, the whole library can be pre-warmed in the background in minutes.

**Tech Stack:** Swift, Accelerate/vDSP (FFT, autocorrelation), AVFoundation (`AVAudioFile` decode),
GRDB (cache), iTunes Search API (preview URLs). **No GPL DSP libraries** — see constraints.

## Global Constraints

- **No GPL/aubio/Essentia dependencies.** This app is distributed; use Apple-native
  Accelerate/vDSP only. (aubio is GPLv3, Essentia is AGPL — both unacceptable for distribution.)
- **macOS 13+** (existing floor, `Package.swift`).
- **Keep the line** `BPM and key data provided by [GetSongBPM](https://getsongbpm.com).` in
  `README.md` **only while** GetSongBPM is still shipped (see Phase 3 — attribution changes when the
  source changes; do not silently drop it).
- `CamelotKey` is the source of truth for Camelot values; DSP must output a `CamelotKey`, never a
  raw string.
- Features cached without a TTL today — Phase 2 adds a `source`/`confidence`-aware invalidation so
  switching providers doesn't strand stale rows.

---

## Spike evidence (already gathered — do not re-investigate)

Ran librosa 0.11 on real Apple preview clips for three known tracks (`scratchpad/clips/`):

| track | detected BPM | truth | detected key→Camelot | truth |
|---|---|---|---|---|
| deadmau5 – Strobe | 89.1 ✗ | 128 | G♯m → **1A** ✓ | G♯m / 1A |
| Eagles – Hotel California | 73.8 ✓ | 75 | D → **10B** ✓ | 10B (GetSongBPM) |
| Skrillex – Bangarang | 172.3 ✗ | ~110 | Fm → 4A (unverified) | — |

**Conclusions that shape this plan:**
1. **Coverage solved** — Apple's preview API returned all three (incl. Skrillex, which GetSongBPM
   lacks entirely). `previewUrl` exists for ~the whole catalog.
2. **Key/Camelot is reliable on 30s clips** — 2/2 exact. Chromagram + Krumhansl–Schmuckler profile
   matching is the algorithm that worked.
3. **BPM is the risk.** Two failure modes: (a) octave errors (half/double), and (b) the preview
   section may not contain the main beat (Strobe's preview is its ambient intro — unrecoverable by
   any algorithm). A naive tempo prior made it worse (broke the correct one). BPM needs a real
   algorithm + a **confidence** signal + octave-folding into an expected band, and must degrade
   gracefully (nil BPM, key-only) when confidence is low.

---

## File structure

- **Create** `Sources/AutocrateCore/DSP/TempoEstimator.swift` — vDSP onset-envelope + autocorrelation
  tempo, returns `(bpm: Double, confidence: Double)`.
- **Create** `Sources/AutocrateCore/DSP/KeyEstimator.swift` — chroma (FFT→pitch-class) + K-S profile
  correlation, returns `(camelot: CamelotKey, confidence: Double)`.
- **Create** `Sources/AutocrateCore/DSP/AudioDecoder.swift` — `AVAudioFile`/`AVAudioPCMBuffer` →
  mono `[Float]` at a fixed sample rate (22050).
- **Create** `Sources/AutocrateCore/Data/PreviewDSPProvider.swift` — `FeatureProvider` impl tying
  resolve → download → decode → estimate → `CachedFeature`.
- **Modify** `Sources/AutocrateCore/Data/iTunesResolver.swift` — add `previewUrl` to `CatalogMatch`
  + `parse`.
- **Modify** `Sources/AutocrateCore/Data/FeatureCache.swift` — migration v2 adds `confidence` REAL;
  `CachedFeature` gains `confidence: Double?`.
- **Modify** `Sources/AutocrateCore/Pipeline/Ranker.swift` (+ `CandidatePipeline`) — weight Camelot;
  treat BPM as best-effort / confidence-gated.
- **Create** `Sources/autocrate-dsp-probe/main.swift` — Phase 0 gate harness (reuses the existing
  `autocrate-probe` pattern).
- **Modify** `Package.swift` — add the `autocrate-dsp-probe` executable target.

---

## Phase 0 — Swift DSP prototype + GO/NO-GO gate (do this first)

**Why:** The whole migration rests on "Swift/vDSP can match the librosa spike." Prove it on the same
three clips before building anything else. If BPM cannot be made reliable, we stop and reconsider
(e.g. key-only matching, or a hybrid that keeps an API for BPM).

### Task 0: DSP probe harness + decode

**Files:**
- Create: `Sources/autocrate-dsp-probe/main.swift`
- Create: `Sources/AutocrateCore/DSP/AudioDecoder.swift`
- Modify: `Package.swift` (add executable target `autocrate-dsp-probe`, product + target)

**Interfaces:**
- Produces: `AudioDecoder.monoSamples(url: URL, sampleRate: Double) async throws -> [Float]`

- [ ] **Step 1:** Add the `autocrate-dsp-probe` executable target to `Package.swift` (mirror the
  existing `autocrate-probe` target block).
- [ ] **Step 2:** Implement `AudioDecoder.monoSamples` using `AVAudioFile` → `AVAudioPCMBuffer`,
  downmix to mono, resample to 22050 (use `AVAudioConverter`). Return `[Float]`.
- [ ] **Step 3:** In `main.swift`, hardcode the three `scratchpad/clips/*.m4a` paths, decode each,
  print sample count + duration. Run: `swift run autocrate-dsp-probe`. Expected: ~660k samples
  (29.97s × 22050) per clip.

### Task 1: Key estimator (validated approach — implement to match librosa)

**Files:**
- Create: `Sources/AutocrateCore/DSP/KeyEstimator.swift`
- Test: `Tests/AutocrateCoreTests/KeyEstimatorTests.swift`

**Interfaces:**
- Produces: `KeyEstimator.estimate(_ samples: [Float], sampleRate: Double) -> (camelot: CamelotKey, confidence: Double)`

**Algorithm (proven in spike):** FFT magnitude spectrum (vDSP) → fold bins into 12 pitch classes
(chromagram, mean over frames) → correlate against the 12 rotations of the Krumhansl–Schmuckler
major and minor profiles → best (tonic, mode) → map to Camelot via the existing wheel. Profiles
(verbatim from the spike):
`MAJ = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88]`,
`MIN = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17]`.
Pitch-class→Camelot mapping is in `scratchpad/clips/analyze.py` (CAM_MAJ/CAM_MIN) — port it.

- [ ] **Step 1:** Write `KeyEstimatorTests` asserting Strobe clip → `CamelotKey("1A")` and Hotel
  California clip → `CamelotKey("10B")` (the spike's ground truth). Gate the test on the clip files
  existing; skip if absent.
- [ ] **Step 2–N:** Implement chroma + K-S correlation until both pass. **Gate:** must reproduce 2/2.

### Task 2: Tempo estimator + confidence (the risk)

**Files:**
- Create: `Sources/AutocrateCore/DSP/TempoEstimator.swift`
- Test: `Tests/AutocrateCoreTests/TempoEstimatorTests.swift`

**Interfaces:**
- Produces: `TempoEstimator.estimate(_ samples: [Float], sampleRate: Double, band: ClosedRange<Double>) -> (bpm: Double, confidence: Double)`

**Algorithm:** spectral-flux onset envelope (vDSP) → autocorrelation of the onset envelope → pick
the lag peak whose BPM (after octave-folding into `band`, default `90...180`) has the strongest,
sharpest peak; `confidence` = normalized peak prominence. Low prominence ⇒ low confidence ⇒ caller
drops BPM.

- [ ] **Step 1:** Write `TempoEstimatorTests`: Hotel California clip → within ±3 BPM of 75 (folded);
  Strobe clip → **either** ~128 **or** low confidence (assert: `bpm≈128 OR confidence < 0.5`). This
  encodes "be right or admit you don't know."
- [ ] **Step 2–N:** Implement until the test passes.

### ⛔ Phase 0 GATE

- [ ] Key: 2/2 Camelot correct on the spike clips.
- [ ] Tempo: Hotel California within ±3 BPM **and** Strobe either correct or flagged low-confidence.
- [ ] **Decision:** If tempo cannot meet the bar even with confidence gating, STOP and bring options
  to the user (key-only matching; or hybrid DSP-key + API-BPM). Do not proceed to Phase 1 on a
  failing gate.

---

## Phase 1 — PreviewDSPProvider (outline; detail after Phase 0)

- Extend `iTunesResolver`: add `previewUrl: URL?` to `CatalogMatch` and `parse` (the iTunes result
  has `previewUrl`). Add a test feeding a captured JSON body asserting `previewUrl` is parsed.
- Create `PreviewDSPProvider: FeatureProvider`: `resolve` (artist,title) → `previewUrl` → download
  clip (URLSession) → `AudioDecoder.monoSamples` → `KeyEstimator` + `TempoEstimator` →
  `CachedFeature(source: "dsp", confidence:, state: .found/.miss)`. Miss when no preview or
  confidence too low for both features.
- Tests with a stubbed resolver + a local fixture clip (reuse `StubURLProtocol`).

## Phase 2 — Cache + wiring (outline)

- GRDB migration v2: add `confidence` REAL column; add `confidence: Double?` to `CachedFeature`.
- Provider selection in `MatchEngine`/`FeatureHydrator` init (inject `PreviewDSPProvider`).
- Invalidation: re-fetch rows whose `source != "dsp"` (so the GetSongBPM-era rows get re-analyzed)
  instead of the unsafe file `rm`. See memory `autocrate-cache-clear-unsafe-while-app-open`.
- **Latency win:** with local analysis there is no 1-req/s API throttle. Add a background pre-warm
  task (raise/remove `FeatureHydrator.cap`, parallelize downloads) so opening the panel is instant
  once warm. This is what actually fixes "the song is over before results appear."

## Phase 3 — Ranking + cleanup (outline)

- `Ranker`/`CandidatePipeline`: weight Camelot relation higher; make BPM a soft factor that is
  skipped (not penalized) when `confidence` is low or BPM is nil. Update tests.
- Decide GetSongBPM's fate: remove, or keep behind a flag as a BPM fallback for low-confidence
  clips. Update the `README.md` attribution line to match what actually ships.

---

## Key decisions (recommended resolutions)

1. **DSP library:** Accelerate/vDSP, **not** aubio/Essentia — licensing (GPL/AGPL) blocks
   distribution. More work, but the only shippable option.
2. **BPM policy: HYBRID (chosen 2026-06-24, post Phase 0 gate).** Camelot always comes from DSP
   (full coverage, validated). BPM comes from GetSongBPM where it has the track; DSP-BPM is used only
   when its confidence clears a threshold; otherwise BPM is nil and matching leans on Camelot.
   Ranking is key-dominant. Implemented as a `HybridFeatureProvider` wrapping `PreviewDSPProvider`
   (primary) + `GetSongBpmClient` (BPM fallback) — both behind the existing `FeatureProvider` seam.
   Rationale: Phase 0 showed DSP key is reliable but DSP-BPM confidence doesn't yet separate
   correct from wrong, so we don't trust low-confidence DSP BPM; the API backfills where it can.
3. **Warm strategy:** background pre-warm (now viable since analysis is local/unthrottled) — solves
   coverage **and** latency together.
4. **Migration shape:** additive via the `FeatureProvider` seam — no pipeline rewrite; GetSongBPM
   can stay as an optional fallback during transition.

## Risks

- **BPM accuracy** (primary) — mitigated by confidence gating + Phase 0 gate; fallback is key-only.
- **Preview section** sometimes lacks the beat (Strobe) — inherent; confidence gating handles it.
- **DSP correctness in Swift** — vDSP chroma/onset code is fiddly; Phase 0 de-risks against librosa
  ground truth before committing.
- **Bandwidth** — full warm ≈ 1–2 GB of clips once; lazy + cached + background.

## Effort estimate

Phase 0 (gate): ~1–2 days · Phase 1: ~1 day · Phase 2: ~0.5–1 day · Phase 3: ~0.5–1 day. Total
~3–5 days, plus DSP tuning iterations concentrated in Phase 0.
