# Autocrate — v1 Build Plan (Claude Code Handoff)

## North star

Autocrate is a native macOS menu-bar utility that helps a heavy Apple Music listener find the *next* track to play. It reads whatever is currently playing as the seed, looks up its tempo and key, and surfaces a ranked shortlist of harmonically- and tempo-compatible tracks to play next. It does **not** mix (Apple Music's AutoMix already does that at playback); it curates the setlist AutoMix runs on. v1 is show-only — the user adds picks to their own queue manually.

---

## v1 scope

**In**
- Read the now-playing Apple Music track automatically (no typing).
- Look up seed BPM + Camelot via GetSongBPM, cached locally.
- Build a candidate pool from the user's own library (tight) and, in the final phase, from GetSongBPM catalog search (wider net).
- Run the filter pipeline: coarse genre exclude → BPM band → Camelot match → ranked shortlist.
- Menu-bar panel showing the seed and the ranked shortlist (BPM, Camelot, genre per row).
- Minimalist stealth theme, monospace.

**Out (deferred — see v2 section)**
- Raycast-style global-hotkey search panel.
- Auto-queue / auto-add to Apple Music.
- DSP audio analysis fallback.
- Sub-genre hard wall (Apple's library genre tag proven too coarse).
- Soft genre bias / wild-card mode.
- MusicKit catalog/playback integration, Apple Developer Program.
- iOS or any second platform.

---

## Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language / UI | Swift + SwiftUI | `MenuBarExtra` for the menu-bar shell (macOS 13+). |
| Now-playing + library read | ScriptingBridge → Music.app | Typed bridge; needs Automation (TCC) permission, user-granted. |
| Feature data | GetSongBPM REST API | Free; **mandatory backlink** to getsongbpm.com in About. BPM + key, plus `/tempo/` and `/key/` search endpoints for discovery. |
| Catalog resolve (phase 6) | iTunes Search API | Free, no auth. Confirms a candidate exists on Apple Music + gives 30s preview URL. |
| Local cache | GRDB.swift (SQLite) | Type-safe, lightweight. Single SPM dependency. |
| Logging | os.Logger (built-in) | Keep dependencies minimal. |

Keep the dependency list to **GRDB only**. The stealth/minimal ethos applies to the codebase too.

---

## Cost & prerequisites

- **Cost: $0 for v1 self-use.** Local builds run with a free Apple ID personal team. The $99/yr Apple Developer Program is only for notarized distribution or MusicKit — both out of scope.
- Xcode (latest), macOS 13+ target.
- GetSongBPM API key — register a free key, store outside source (e.g. a gitignored `Secrets.swift` or env).
- On first run, the app will prompt for permission to control Music.app — handle the denied/not-yet-granted state gracefully.

---

## Architecture (modules)

```
Autocrate/
  App/                 MenuBarExtra entry, app lifecycle
  Theme/               Design tokens (colors, fonts, spacing)
  Models/              Track, CamelotKey, MatchResult, enums
  Matching/            CamelotWheel, BpmBand, Ranker  (pure, no I/O)
  Music/               NowPlayingReader, LibraryReader (ScriptingBridge)
  Data/                GetSongBpmClient, FeatureCache (GRDB), iTunesResolver
  Pipeline/            CandidatePipeline (exclude → band → camelot → rank)
  UI/                  MenuPanelView, SeedHeader, ShortlistRow, StateViews
```

Design rule: `Matching/` is pure logic with zero I/O so it can be fully unit-tested in isolation. Everything else depends on it, not the reverse.

---

## Data model & cache

`FeatureCache` table (GRDB):

| column | type | notes |
|---|---|---|
| `id` | TEXT PK | normalized `artist|title` hash, or GetSongBPM id when known |
| `title` | TEXT | |
| `artist` | TEXT | |
| `bpm` | REAL? | nullable |
| `camelot` | TEXT? | e.g. "8A" |
| `musical_key` | TEXT? | e.g. "A minor" |
| `source` | TEXT | `getsongbpm` / `manual` (later: `dsp`) |
| `state` | TEXT | `found` / `unsure` / `miss` |
| `fetched_at` | INTEGER | unix seconds, for staleness |

Three-state lookup result: `found` (GetSongBPM had it), `unsure` (low-confidence, reserved for the future DSP path), `miss` (no data — excluded from harmonic matching). Every lookup result is written to cache, including misses, so each track is only ever fetched once.

---

## Matching engine spec

**Camelot compatibility** — given seed key `N` + letter `L` (N = 1..12, L ∈ {A,B}), a candidate key is compatible if it is one of:
- **Perfect**: same `N`, same `L`.
- **Adjacent**: `N±1` (wrap 12→1, 1→12), same `L` — neighbouring keys, slight energy shift.
- **Relative**: same `N`, opposite `L` — relative major/minor.

Rank weight: perfect > relative > adjacent. (Energy-boost +2 and diagonal moves are deliberately excluded from v1 — add later if wanted.)

**BPM band** — a candidate passes if its BPM is within ±6% of the seed:
`seed.bpm * 0.94 ≤ candidate.bpm ≤ seed.bpm * 1.06`.
Enhancement (optional in v1): also accept half/double-time matches (candidate.bpm × 2 or ÷ 2 falls in band) to catch e.g. a 64-BPM track against a 128 seed — flag these as "tempo-shifted."

**Ranking score** — combine normalized BPM closeness with the Camelot relationship weight; sort descending. Ties broken by BPM closeness.

This is where the Skrillex problem dissolves: a 140-BPM track against a ~124 seed is outside the band and never surfaces — no genre data required.

---

## Filter pipeline

Seed → candidate pool → **coarse genre exclude** → **BPM band** → **Camelot match** → ranked shortlist.

- **Coarse genre exclude**: keep only an allowlist of electronic-adjacent umbrellas, drop everything else. Default allowlist (from the user's actual library distribution): `Dance, Electronic, House, Techno, Trance, Dubstep, Bass, Electronica`. Make it editable in settings. This reliably drops country/pop/rock/rap/metal/etc. but does **not** attempt sub-genre separation (Apple's tag can't support it).
- **BPM band** and **Camelot match**: as specified above.
- Known v1 gap (accepted): a non-house electronic track at house tempo (e.g. 128-BPM trance tagged "Dance") can pass all three gates. This is the labeled v2 problem — do not try to solve it in v1.

---

## UI & theming

**Layout**
- `MenuBarExtra` icon in the status bar → click opens a compact panel.
- Panel top: seed header — now-playing title/artist, its BPM + Camelot, lookup state.
- Panel body: ranked shortlist rows — title, artist, BPM, Camelot badge, genre. Show-only (no auto-queue). Row tap **opens the track in Apple Music**: `reveal` the library track via ScriptingBridge, or deep-link a catalog track via its `music.apple.com` URL (phase 6). The user does the final "add to queue" gesture themselves. Copy "Artist – Title" to clipboard is demoted to a secondary action (modifier-click) as a fallback. (Programmatic append to Apple Music's Up Next isn't reliably exposed via AppleScript — this is *why* v1 is show-only.)
- States to design explicitly: loading, nothing playing, seed has no data (MISS), no compatible matches, Music.app permission not granted.
- About/settings: GetSongBPM attribution backlink (required), allowlist editor, BPM band width.

**Theme — minimalist / stealth**
Near-black, monospace, restrained. Suggested tokens (tune to taste):

```
--bg:            #0B0B0C   (near-black)
--surface:       #141416
--border:        rgba(255,255,255,0.06)
--text-primary:  #E8E8E6
--text-secondary:#8A8A85
--accent:        one restrained accent (used for Camelot badge tint + top match)
```

- Numerals (BPM, Camelot) use **tabular** figures so columns align.
- **Accent allowed** (restrained): tint the Camelot badge by wheel position; a single accent may also mark the top-ranked match. Everything else stays monochrome near-black.
- **Fonts (locked)**:
  - `--font-mono: "JetBrains Mono"` — the workhorse for all readable UI and data (track names, labels, lists).
  - `--font-display: "Geist Pixel Square"` — reserved for the big expressive numerals only (BPM readout, Camelot badge). Do **not** use the pixel font for body/list text; it's a display face and gets noisy at small sizes.
  - Both are open-source and free to bundle. Download the font files from vercel.com/font (or extract from the `geist` npm package), add the `.otf`/`.ttf` to the Xcode project, and register them via `ATSApplicationFontsPath` in Info.plist (or `CTFontManagerRegisterFontsForURL` at launch). Geist Pixel has 5 variants (Square, Grid, Circle, Triangle, Line) — Square is the default; swapping is a one-line change if a different texture is wanted.

---

## Build phases (ordered for Claude Code)

Each phase is independently verifiable. Build in order — logic first, then I/O, then UI.

**Phase 0 — Scaffold**
SwiftUI macOS app, `MenuBarExtra` shell, theme tokens stubbed, fonts loaded.
*Done when:* an icon appears in the menu bar and clicking it shows an empty themed panel.

**Phase 1 — Matching engine (pure logic)**
`CamelotKey` model + wheel, compatibility rules, BPM band, ranker. No I/O.
*Done when:* unit tests cover perfect/adjacent/relative matches, wrap-around (12↔1), and BPM-band edges, and all pass.

**Phase 2 — Now-playing reader**
ScriptingBridge `NowPlayingReader`: current track title/artist/genre; handle stopped + permission-denied states.
*Done when:* it returns the live playing track, and a clear error state when nothing's playing or permission is missing.

**Phase 3 — GetSongBPM client + cache**
`GetSongBpmClient` (search → resolve → bpm/key), `FeatureCache` (GRDB) with the three-state result. Attribution link wired into About.
*Done when:* a title/artist returns FOUND (with BPM+Camelot) or MISS, the result is cached, and a second lookup hits cache not network.

**Phase 4 — Library pool + pipeline**
`LibraryReader` (ScriptingBridge) builds the candidate set; `CandidatePipeline` runs exclude → band → Camelot → rank against the seed.
*Done when:* a seed produces a correct ranked shortlist drawn from the library, with the coarse exclude and BPM band visibly filtering.

**Phase 5 — Menu-bar UI + theme**
Assemble the panel: seed header, shortlist rows, all states, full theme. Row tap opens the track in Apple Music (reveal for library tracks); modifier-click copies to clipboard.
*Done when:* the whole loop works visually from a single click — playing track in, ranked shortlist out.

**Phase 6 — Catalog expand (closes v1)**
"Discover" section: GetSongBPM `/tempo/` + `/key/` search for fresh candidates → `iTunesResolver` confirms each is on Apple Music → same pipeline → shown below the library matches.
*Done when:* with the library exhausted, the panel still surfaces compatible tracks the user doesn't own, each confirmed playable on Apple Music.

---

## Deferred to v2

DSP audio-analysis fallback for MISS tracks (aubio, **BPM-only** — key-from-preview is unreliable and must not feed Camelot); MusicKit catalog/playback integration; Raycast-style global-hotkey panel; sub-genre wall (needs a granular genre source — MusicKit `genreNames` or Beatport); soft genre bias + wild-card mode; auto-queue into Apple Music.

---

## Decisions — resolved

1. **Stack** — native Swift / SwiftUI. ✅
2. **`--font-display`** — Geist Pixel Square (numerals only); JetBrains Mono for everything else. ✅
3. **Accent** — one restrained accent allowed (Camelot badge tint + top match). ✅
4. **Row-tap action** — opens the track in Apple Music (reveal library track / deep-link catalog track); clipboard copy demoted to modifier-click fallback. Recommended default — flag if you'd rather it be clipboard-primary.
