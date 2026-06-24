# Autocrate v1 — Design Spec

**Date:** 2026-06-24
**Status:** Approved design, ready for implementation planning
**Source:** Derived from `autocrate/autocrate-v1-claude-code-plan.md`, refined via brainstorming.

---

## 1. Overview

Autocrate is a native macOS menu-bar utility that helps a heavy Apple Music listener pick the *next* track to play. It reads the now-playing track as a seed, looks up its tempo (BPM) and key (Camelot), and surfaces a ranked shortlist of harmonically- and tempo-compatible tracks.

It does **not** mix — Apple Music's AutoMix handles playback transitions. Autocrate curates the setlist AutoMix runs on. v1 is **show-only**: the user adds picks to their own queue manually.

### North-star user loop
Playing track in → ranked compatible shortlist out → user taps a row → track opens in Apple Music → user adds it to their own queue.

---

## 2. Scope

### In v1
- Read the now-playing Apple Music track automatically (no typing).
- Look up seed BPM + Camelot via GetSongBPM, cached locally.
- Build a candidate pool from the user's own library; in the final phase, widen with GetSongBPM catalog search.
- Filter pipeline: coarse genre exclude → BPM band → Camelot match → ranked shortlist.
- **Half/double-time BPM matching** (e.g. 64 BPM candidate against a 128 seed), flagged `tempoShifted`.
- Menu-bar panel: seed header + ranked shortlist (BPM, Camelot, genre per row), with all edge-state views.
- Minimalist stealth theme, monospace.

### Out of v1 (deferred to v2)
- Settings UI for the genre allowlist, BPM band width, and per-session lookup cap — these are **hardcoded sensible defaults** in v1.
- Raycast-style global-hotkey search panel.
- Auto-queue / auto-add to Apple Music.
- DSP audio-analysis fallback for tracks with no GetSongBPM data.
- Sub-genre hard wall (Apple's library genre tag is too coarse to support it).
- Soft genre bias / wild-card mode.
- MusicKit catalog/playback integration; Apple Developer Program.
- iOS or any second platform.

### Design decisions baked in (resolved during brainstorming)
1. **One cohesive v1 spec.** All seven phases are milestones within a single design, not separate specs.
2. **Cache population = lazy, seed-anchored, capped.** No upfront background batch. See §6.
3. **Half/double-time BPM matching is IN.** Allowlist editor, band-width control, and lookup-cap control are OUT (hardcoded).
4. **Row tap opens the track in Apple Music** (reveal for library tracks; deep-link for catalog tracks in phase 6). Clipboard copy is demoted to a modifier-click fallback.

---

## 3. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language / UI | Swift + SwiftUI | `MenuBarExtra` shell (macOS 13+). |
| Now-playing + library read | ScriptingBridge → Music.app | Typed bridge; needs Automation (TCC) permission, user-granted. |
| Feature data | GetSongBPM REST API | Free; **mandatory backlink** to getsongbpm.com in About. Returns `tempo`, `key_of`, `open_key`. `/tempo/` + `/key/` search endpoints for discovery. |
| Catalog resolve (phase 6) | iTunes Search API | Free, no auth. Confirms a candidate exists on Apple Music + gives a 30s preview URL. |
| Local cache | GRDB.swift (SQLite) | Type-safe, lightweight. The **only** SPM dependency. |
| Logging | os.Logger (built-in) | No extra dependency. |

Dependency budget: **GRDB only.** The stealth/minimal ethos applies to the codebase.

### Cost & prerequisites
- **$0 for v1 self-use.** Local builds run under a free Apple ID personal team. The $99/yr Apple Developer Program is only needed for notarized distribution or MusicKit — both out of scope.
- Xcode (latest), macOS 13+ target.
- GetSongBPM API key — free registration, stored outside source control (gitignored `Secrets.swift` or env var).
- First run prompts for permission to control Music.app; the denied / not-yet-granted state is handled gracefully.

---

## 4. Architecture

```
Autocrate/
  App/        MenuBarExtra entry, app lifecycle
  Theme/      Design tokens (colors, fonts, spacing)
  Models/     Track, CamelotKey, MatchResult, LookupState enums
  Matching/   CamelotWheel, BpmBand, Ranker, KeyToCamelot   (PURE, no I/O)
  Music/      NowPlayingReader, LibraryReader (ScriptingBridge)
  Data/       GetSongBpmClient, FeatureCache (GRDB), iTunesResolver
  Pipeline/   CandidatePipeline + FeatureHydrator
  UI/         MenuPanelView, SeedHeader, ShortlistRow, StateViews
```

### Design rules
- **`Matching/` is pure logic with zero I/O** — fully unit-testable in isolation. Everything depends on it, not the reverse. `KeyToCamelot` (musical-key → Camelot static map) lives here.
- **`FeatureHydrator` is separated from `CandidatePipeline`.** The hydrator owns the capped, throttled lookup loop (the side-effecting part); the pipeline is pure filtering/ranking over already-hydrated candidates. This keeps the filter logic testable without network.
- Each unit has one clear purpose, a well-defined interface, and can be reasoned about independently.

---

## 5. Data model & cache

`FeatureCache` table (GRDB):

| column | type | notes |
|---|---|---|
| `id` | TEXT PK | normalized `artist\|title` hash, or GetSongBPM id when known |
| `title` | TEXT | |
| `artist` | TEXT | |
| `bpm` | REAL? | nullable |
| `camelot` | TEXT? | e.g. `"8A"` |
| `musical_key` | TEXT? | e.g. `"A minor"` |
| `source` | TEXT | `getsongbpm` / `manual` (later: `dsp`) |
| `state` | TEXT | `found` / `unsure` / `miss` |
| `fetched_at` | INTEGER | unix seconds |

### Lookup states
- `found` — GetSongBPM returned BPM + key.
- `unsure` — low-confidence; **reserved** for the future DSP path, not produced in v1.
- `miss` — no data; excluded from harmonic matching.

Every lookup result is written to cache, **including misses**, so each track is fetched at most once, ever.

### Staleness
**No TTL.** A track's BPM and key are immutable, so cached features never expire. The only re-fetch path is a manual/explicit refresh (not exposed in v1 UI). `fetched_at` is recorded for diagnostics and future use.

---

## 6. Cache population — lazy, seed-anchored, capped

This is the load-bearing decision for v1. GetSongBPM's rate limits are undocumented, and the BPM band cannot filter a candidate without that candidate's BPM. So population is **lazy** rather than an upfront batch:

```
now-playing → seed
  → seed feature lookup (cache → else API → cache)
  → LibraryReader: read all library tracks
  → genre allowlist exclude (hardcoded list)
  → FeatureHydrator: walk genre-allowed candidates in a deterministic order
        (recently-added first), and for each:
          - cache hit  → use cached features
          - cache miss → API fetch (throttled ~1 req/s),
                         write result (found/miss) to cache
        stop when the per-session cap (N = 50) is reached OR the list ends
  → CandidatePipeline (pure): operates only on candidates with cached
        features → BPM band → Camelot match → rank
  → shortlist
```

### Parameters (hardcoded defaults in v1)
- **Per-session lookup cap:** `N = 50` new fetches per session.
- **Throttle:** ~1 request/second.
- **Lookup order:** deterministic — recently-added library tracks first (a sensible bias toward tracks the user currently cares about), then continue through the library on subsequent sessions.

### Consequence (accepted)
Early sessions show a thin shortlist because the cache is cold. Over repeated use the cache fills and shortlists fatten. The UI communicates this explicitly via the **indexing** state (§8). This trade — slower ramp-up in exchange for never hammering the API — was chosen deliberately over background batch warming.

---

## 7. Matching engine

All pure logic in `Matching/`, fully unit-tested before any I/O exists.

### Camelot compatibility
Given seed key number `N` (1..12) and letter `L` ∈ {A, B}, a candidate key is compatible if it is:
- **Perfect** — same `N`, same `L`.
- **Relative** — same `N`, opposite `L` (relative major/minor).
- **Adjacent** — `N ± 1` (wrap 12→1, 1→12), same `L`.

Rank weight: **perfect > relative > adjacent.** Energy-boost (+2) and diagonal moves are excluded from v1.

### Key → Camelot conversion
GetSongBPM returns `key_of` (musical key, e.g. "A minor") and `open_key` (OpenKey notation). `KeyToCamelot` is a static 24-entry map (12 keys × major/minor) producing the Camelot value used throughout matching. Pure function, unit-tested against all 24 keys plus the enharmonic spellings GetSongBPM may emit.

### BPM band (with half/double-time)
Base band: candidate passes if `seed.bpm × 0.94 ≤ candidate.bpm ≤ seed.bpm × 1.06`.

**Half/double extension:** a candidate also passes if `candidate.bpm × 2` **or** `candidate.bpm ÷ 2` lands in the base band (catches e.g. a 64-BPM track against a 128 seed). Candidates matched via the ×2/÷2 path are flagged `tempoShifted` so the UI can badge them.

### Ranking
Score combines normalized BPM-closeness with the Camelot relationship weight; sort descending. Ties broken by BPM closeness. Exact-tempo matches rank above `tempoShifted` matches of otherwise-equal score.

### Why this dissolves the "Skrillex problem"
A 140-BPM track against a ~124 seed is outside the band and never surfaces — no genre data required.

---

## 8. Filter pipeline

`Seed → candidate pool → coarse genre exclude → BPM band → Camelot match → ranked shortlist.`

- **Coarse genre exclude:** keep only an allowlist of electronic-adjacent umbrellas; drop everything else. Hardcoded default (from the user's actual library distribution): `Dance, Electronic, House, Techno, Trance, Dubstep, Bass, Electronica`. Reliably drops country/pop/rock/rap/metal. Does **not** attempt sub-genre separation (Apple's tag can't support it).
- **BPM band** and **Camelot match:** as specified in §7.

### Accepted v1 gap
A non-house electronic track at house tempo (e.g. 128-BPM trance tagged "Dance") can pass all three gates. This is the labeled v2 problem and is **not** solved in v1.

---

## 9. UI & theming

### Layout
- `MenuBarExtra` icon in the status bar → click opens a compact panel.
- **Seed header:** now-playing title/artist, its BPM + Camelot, lookup state.
- **Shortlist body:** ranked rows — title, artist, BPM, Camelot badge, genre, and a `tempoShifted` marker where applicable. Show-only.
- **Row tap → opens the track in Apple Music:** `reveal` the library track via ScriptingBridge, or (phase 6) deep-link a catalog track via its `music.apple.com` URL. The user performs the final "add to queue" gesture. **Modifier-click → copy "Artist – Title"** to clipboard (secondary fallback). Programmatic append to Apple Music's Up Next isn't reliably exposed via AppleScript — this is *why* v1 is show-only.

### Explicit states to design
- `loading`
- `nothingPlaying`
- `seedMiss` — seed has no GetSongBPM data
- `noMatches` — nothing compatible in the hydrated pool
- `indexing` — cache warming; shows "showing N of M, more coming"
- `permissionDenied` — Music.app Automation permission not granted

### About / settings
- GetSongBPM attribution **backlink (required)**.
- v1 has no allowlist/band/cap editors (deferred). About screen is primarily the attribution + app info.

### Theme — minimalist / stealth
Near-black, monospace, restrained.

```
--bg:             #0B0B0C   (near-black)
--surface:        #141416
--border:         rgba(255,255,255,0.06)
--text-primary:   #E8E8E6
--text-secondary: #8A8A85
--accent:         one restrained accent (Camelot badge tint + top match)
```

- BPM/Camelot numerals use **tabular** figures so columns align.
- **One restrained accent:** tint the Camelot badge by wheel position; the accent may also mark the top-ranked match. Everything else stays monochrome near-black.
- **Fonts (locked):**
  - `--font-mono: "JetBrains Mono"` — all readable UI and data (track names, labels, lists).
  - `--font-display: "Geist Pixel Square"` — **reserved for the big expressive numerals only** (BPM readout, Camelot badge). Not for body/list text.
  - Both open-source and free to bundle. Add the `.otf`/`.ttf` to the Xcode project and register via `ATSApplicationFontsPath` in Info.plist (or `CTFontManagerRegisterFontsForURL` at launch). Geist Pixel Square is the default variant; swapping is a one-line change.

---

## 10. Build milestones

Phases of one spec, built in order — logic first, then I/O, then UI. Each is independently verifiable.

**P0 — Scaffold.** SwiftUI macOS app, `MenuBarExtra` shell, theme tokens stubbed, fonts loaded.
*Done when:* an icon appears in the menu bar and clicking it shows an empty themed panel.

**P1 — Matching engine (pure logic, TDD).** `CamelotKey` + wheel, compatibility rules, `KeyToCamelot`, BPM band (incl. half/double), ranker. No I/O.
*Done when:* unit tests cover perfect/relative/adjacent matches, wrap-around (12↔1), BPM-band edges, half/double-time matches, and all 24 key conversions — all passing.

**P2 — Now-playing reader.** ScriptingBridge `NowPlayingReader`: current track title/artist/genre; handles stopped + permission-denied states.
*Done when:* it returns the live playing track and a clear error state when nothing is playing or permission is missing.

**P3 — GetSongBPM client + cache.** `GetSongBpmClient` (search → resolve → bpm/key), `FeatureCache` (GRDB) with the three-state result. Attribution link wired into About.
*Done when:* a title/artist returns `found` (BPM+Camelot) or `miss`, the result is cached, and a second lookup hits cache, not network.

**P4 — Library pool + hydrator + pipeline.** `LibraryReader` builds the candidate set; `FeatureHydrator` runs the capped/throttled lazy lookup; `CandidatePipeline` runs exclude → band → Camelot → rank against the seed.
*Done when:* a seed produces a correct ranked shortlist from hydrated library candidates, with coarse exclude and BPM band visibly filtering, and the lookup cap/throttle respected.

**P5 — Menu-bar UI + theme.** Assemble the panel: seed header, shortlist rows, **all states from §8**, full theme. Row tap opens the track in Apple Music; modifier-click copies.
*Done when:* the whole loop works visually from a single click — playing track in, ranked shortlist out — and every state renders.

**P6 — Catalog expand (closes v1).** "Discover" section: GetSongBPM `/tempo/` + `/key/` search for fresh candidates → `iTunesResolver` confirms each is on Apple Music → same pipeline → shown below the library matches.
*Done when:* with the library exhausted, the panel still surfaces compatible tracks the user doesn't own, each confirmed playable on Apple Music.

---

## 11. Testing strategy

- **`Matching/` (P1):** exhaustive unit tests — the core correctness guarantee. Camelot compatibility (all relationships + wrap), BPM band edges, half/double paths, ranking order, all 24 key→Camelot conversions including enharmonic spellings.
- **`Data/` (P3):** cache round-trip (write/read), three-state result mapping, cache-hit avoids network (injected/mocked client), miss caching.
- **`Pipeline/` (P4):** pipeline filtering over a fixed in-memory candidate set (no network); hydrator cap + throttle behavior with a fake clock/client.
- **`Music/` (P2) and `UI/` (P5):** verified manually against live Music.app, since ScriptingBridge and SwiftUI menu-bar behavior resist unit testing. State views verified by driving each state explicitly.

---

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| GetSongBPM rate limit undocumented | Throttle (~1/s) + per-session cap (50) + permanent cache (fetch each track once). |
| ScriptingBridge needs TCC Automation grant | Explicit `permissionDenied` state with guidance; app degrades gracefully. |
| Cold cache = thin early shortlists | `indexing` state communicates "N of M, more coming"; recently-added-first ordering surfaces relevant tracks soonest. |
| GetSongBPM enharmonic key spellings | `KeyToCamelot` map covers enharmonic variants; unit-tested. |
| **Accepted gap:** trance-tagged-"Dance" at house tempo passes all gates | Documented as the v2 sub-genre problem; not solved in v1. |

---

## 13. Out-of-scope reference (v2 backlog)

DSP audio-analysis fallback for `miss` tracks (BPM-only — key-from-preview is unreliable and must not feed Camelot); MusicKit catalog/playback integration; Raycast-style global-hotkey panel; sub-genre wall (needs a granular genre source — MusicKit `genreNames` or Beatport); soft genre bias + wild-card mode; auto-queue into Apple Music; settings editors for allowlist / band width / lookup cap.
